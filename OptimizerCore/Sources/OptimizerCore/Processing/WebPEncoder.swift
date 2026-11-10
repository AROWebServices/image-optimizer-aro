import Foundation
import CoreGraphics
import libwebp

/// WebP encoding through libwebp's advanced API. Supports lossy, lossless and animated output,
/// plus ICC and XMP chunks via libwebpmux.
public enum WebPEncoder {
    public struct Settings: Sendable {
        public var quality: Int
        public var lossless: Bool
        /// 0 (fast) … 6 (smallest). libwebp calls this "method".
        public var effort: Int
        public var iccProfile: Data?
        public var xmp: Data?

        public init(quality: Int, lossless: Bool, effort: Int = 4, iccProfile: Data? = nil, xmp: Data? = nil) {
            self.quality = quality
            self.lossless = lossless
            self.effort = effort
            self.iccProfile = iccProfile
            self.xmp = xmp
        }
    }

    public static func encode(_ image: CGImage, colorSpace: CGColorSpace, settings: Settings) throws -> Data {
        let buffer = try PixelBuffer(image: image, colorSpace: colorSpace)
        var config = try makeConfig(settings)
        var picture = WebPPicture()
        guard WebPPictureInit(&picture) != 0 else { throw OptimizerError.encodingFailed(.webp, "WebPPictureInit failed.") }
        defer { WebPPictureFree(&picture) }
        try importPixels(buffer, into: &picture)

        var writer = WebPMemoryWriter()
        WebPMemoryWriterInit(&writer)
        defer { WebPMemoryWriterClear(&writer) }
        picture.writer = WebPMemoryWrite
        let encoded: Bool = withUnsafeMutablePointer(to: &writer) { pointer in
            picture.custom_ptr = UnsafeMutableRawPointer(pointer)
            return WebPEncode(&config, &picture) != 0
        }
        guard encoded, let mem = writer.mem else {
            throw OptimizerError.encodingFailed(.webp, errorDescription(picture.error_code))
        }
        let data = Data(bytes: mem, count: writer.size)
        return try addMetadata(to: data, settings: settings)
    }

    public static func encodeAnimation(frames: [CGImage], delays: [Double], loopCount: Int,
                                       colorSpace: CGColorSpace, settings: Settings) throws -> Data {
        guard let first = frames.first else { throw OptimizerError.encodingFailed(.webp, "No frames.") }
        var config = try makeConfig(settings)
        var options = WebPAnimEncoderOptions()
        guard WebPAnimEncoderOptionsInit(&options) != 0 else { throw OptimizerError.encodingFailed(.webp, "Animation options failed.") }
        options.anim_params.loop_count = Int32(max(0, loopCount))
        options.minimize_size = settings.effort >= 5 ? 1 : 0
        options.allow_mixed = settings.lossless ? 0 : 1
        guard let encoder = WebPAnimEncoderNew(Int32(first.width), Int32(first.height), &options) else {
            throw OptimizerError.encodingFailed(.webp, "Could not create the animation encoder.")
        }
        defer { WebPAnimEncoderDelete(encoder) }

        var timestamp = 0
        for (index, frame) in frames.enumerated() {
            let buffer = try PixelBuffer(image: frame, colorSpace: colorSpace)
            var picture = WebPPicture()
            guard WebPPictureInit(&picture) != 0 else { throw OptimizerError.encodingFailed(.webp, "WebPPictureInit failed.") }
            try importPixels(buffer, into: &picture)
            let added = WebPAnimEncoderAdd(encoder, &picture, Int32(timestamp), &config) != 0
            WebPPictureFree(&picture)
            guard added else { throw OptimizerError.encodingFailed(.webp, "Frame \(index + 1) could not be added.") }
            let delay = index < delays.count ? delays[index] : 0.1
            timestamp += max(10, Int((delay * 1000).rounded()))
        }
        guard WebPAnimEncoderAdd(encoder, nil, Int32(timestamp), nil) != 0 else {
            throw OptimizerError.encodingFailed(.webp, "Could not finish the animation.")
        }
        var output = WebPData()
        WebPDataInit(&output)
        defer { WebPDataClear(&output) }
        guard WebPAnimEncoderAssemble(encoder, &output) != 0, let bytes = output.bytes else {
            throw OptimizerError.encodingFailed(.webp, "Could not assemble the animation.")
        }
        let data = Data(bytes: bytes, count: output.size)
        return try addMetadata(to: data, settings: settings)
    }

    // MARK: - Helpers

    static func makeConfig(_ settings: Settings) throws -> WebPConfig {
        var config = WebPConfig()
        let quality = Float(min(100, max(1, settings.quality)))
        guard WebPConfigPreset(&config, WEBP_PRESET_DEFAULT, quality) != 0 else {
            throw OptimizerError.encodingFailed(.webp, "WebPConfigPreset failed.")
        }
        config.method = Int32(min(6, max(0, settings.effort)))
        config.thread_level = 1
        config.alpha_quality = 100
        if settings.lossless {
            config.lossless = 1
            // In lossless mode "quality" trades speed for size. 80 is close to the best result at a sane speed.
            config.quality = settings.effort >= 6 ? 100 : 80
            config.exact = 0
        } else {
            config.lossless = 0
            config.quality = quality
            // Sharp YUV conversion keeps thin edges and text crisper at a small speed cost.
            config.use_sharp_yuv = 1
        }
        guard WebPValidateConfig(&config) != 0 else {
            throw OptimizerError.encodingFailed(.webp, "Invalid encoder configuration.")
        }
        return config
    }

    static func importPixels(_ buffer: PixelBuffer, into picture: inout WebPPicture) throws {
        picture.use_argb = 1
        picture.width = Int32(buffer.width)
        picture.height = Int32(buffer.height)
        let imported = buffer.bytes.withUnsafeBufferPointer { pointer -> Bool in
            WebPPictureImportRGBA(&picture, pointer.baseAddress, Int32(buffer.bytesPerRow)) != 0
        }
        guard imported else { throw OptimizerError.encodingFailed(.webp, "Could not import pixels (\(buffer.width)×\(buffer.height)).") }
    }

    /// Wraps a finished bitstream in a container that also carries ICC and XMP chunks.
    static func addMetadata(to bitstream: Data, settings: Settings) throws -> Data {
        guard settings.iccProfile != nil || settings.xmp != nil else { return bitstream }
        return try bitstream.withUnsafeBytes { raw -> Data in
            var input = WebPData(bytes: raw.bindMemory(to: UInt8.self).baseAddress, size: bitstream.count)
            guard let mux = WebPMuxCreate(&input, 1) else { throw OptimizerError.encodingFailed(.webp, "Could not open the bitstream for metadata.") }
            defer { WebPMuxDelete(mux) }
            if let icc = settings.iccProfile {
                try setChunk(mux, fourcc: "ICCP", data: icc)
            }
            if let xmp = settings.xmp {
                try setChunk(mux, fourcc: "XMP ", data: xmp)
            }
            var assembled = WebPData()
            WebPDataInit(&assembled)
            defer { WebPDataClear(&assembled) }
            guard WebPMuxAssemble(mux, &assembled) == WEBP_MUX_OK, let bytes = assembled.bytes else {
                throw OptimizerError.encodingFailed(.webp, "Could not write metadata chunks.")
            }
            return Data(bytes: bytes, count: assembled.size)
        }
    }

    private static func setChunk(_ mux: OpaquePointer, fourcc: String, data: Data) throws {
        try data.withUnsafeBytes { raw in
            var chunk = WebPData(bytes: raw.bindMemory(to: UInt8.self).baseAddress, size: data.count)
            guard WebPMuxSetChunk(mux, fourcc, &chunk, 1) == WEBP_MUX_OK else {
                throw OptimizerError.encodingFailed(.webp, "Could not store the \(fourcc.trimmingCharacters(in: .whitespaces)) chunk.")
            }
        }
    }

    static func errorDescription(_ code: WebPEncodingError) -> String {
        switch code {
        case VP8_ENC_ERROR_OUT_OF_MEMORY, VP8_ENC_ERROR_BITSTREAM_OUT_OF_MEMORY: return "Out of memory."
        case VP8_ENC_ERROR_NULL_PARAMETER: return "Internal error (null parameter)."
        case VP8_ENC_ERROR_INVALID_CONFIGURATION: return "Invalid configuration."
        case VP8_ENC_ERROR_BAD_DIMENSION: return "Image too large for WebP (maximum 16383 pixels per side)."
        case VP8_ENC_ERROR_PARTITION0_OVERFLOW, VP8_ENC_ERROR_PARTITION_OVERFLOW: return "Partition overflow; try a lower quality or effort."
        case VP8_ENC_ERROR_BAD_WRITE: return "Could not write output."
        case VP8_ENC_ERROR_FILE_TOO_BIG: return "Output exceeds 4 GB."
        case VP8_ENC_ERROR_USER_ABORT: return "Aborted."
        default: return "Encoder error \(code.rawValue)."
        }
    }
}
