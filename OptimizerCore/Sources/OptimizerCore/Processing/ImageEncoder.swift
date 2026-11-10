import Foundation
import ImageIO
import CoreGraphics

public struct EncodeOptions: Sendable {
    public var format: OutputFormat
    public var quality: Int
    public var lossless: Bool
    public var progressiveJPEG: Bool
    public var effort: Int
    public var optimizePNGPalette: Bool
    /// Seconds per frame; only read when more than one frame is supplied.
    public var frameDelays: [Double]
    public var loopCount: Int
    /// ICC profile to embed for WebP when the pixels are not sRGB.
    public var iccProfile: Data?

    public init(format: OutputFormat, quality: Int, lossless: Bool, progressiveJPEG: Bool = true, effort: Int = 4,
                optimizePNGPalette: Bool = true, frameDelays: [Double] = [], loopCount: Int = 0, iccProfile: Data? = nil) {
        self.format = format
        self.quality = min(100, max(1, quality))
        self.lossless = lossless
        self.progressiveJPEG = progressiveJPEG
        self.effort = effort
        self.optimizePNGPalette = optimizePNGPalette
        self.frameDelays = frameDelays
        self.loopCount = loopCount
        self.iccProfile = iccProfile
    }
}

public struct EncodedImage {
    public var data: Data
    public var notes: [String]
}

/// Turns upright, already-resized frames into a file in the requested format.
public enum ImageEncoder {
    /// AVIF's system encoder rejects quality 1.0, so lossless requests become the highest lossy level.
    public static let maximumAVIFQuality = 0.99

    public static func encode(frames: [CGImage], options: EncodeOptions, metadata: CGImageMetadata?) throws -> EncodedImage {
        guard let first = frames.first else { throw OptimizerError.encodingFailed(options.format, "Nothing to encode.") }
        var notes: [String] = []
        switch options.format {
        case .webp:
            let colorSpace: CGColorSpace = {
                if options.iccProfile != nil, let space = first.colorSpace, space.model == .rgb { return space }
                return CGColorSpace(name: CGColorSpace.sRGB)!
            }()
            let xmp = metadata.flatMap { MetadataFilter.xmpData($0) }
            let settings = WebPEncoder.Settings(quality: options.quality, lossless: options.lossless, effort: options.effort,
                                                iccProfile: options.iccProfile, xmp: xmp)
            if frames.count > 1 {
                let data = try WebPEncoder.encodeAnimation(frames: frames, delays: options.frameDelays, loopCount: options.loopCount,
                                                           colorSpace: colorSpace, settings: settings)
                notes.append("Animated WebP with \(frames.count) frames.")
                return EncodedImage(data: data, notes: notes)
            }
            let data = try WebPEncoder.encode(first, colorSpace: colorSpace, settings: settings)
            return EncodedImage(data: data, notes: notes)

        case .png:
            var outputFrames = frames
            if frames.count == 1 {
                let outcome = PNGOptimizer.optimize(first, allowPalette: options.optimizePNGPalette)
                outputFrames = [outcome.image]
                if let note = outcome.note { notes.append(note) }
            }
            let data = try encodeWithImageIO(frames: outputFrames, options: options, metadata: metadata, notes: &notes)
            return EncodedImage(data: data, notes: notes)

        case .jpeg, .avif, .heic, .gif:
            let data = try encodeWithImageIO(frames: frames, options: options, metadata: metadata, notes: &notes)
            return EncodedImage(data: data, notes: notes)
        }
    }

    static func encodeWithImageIO(frames: [CGImage], options: EncodeOptions, metadata: CGImageMetadata?, notes: inout [String]) throws -> Data {
        let format = options.format
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, format.utTypeIdentifier as CFString, frames.count, nil) else {
            throw OptimizerError.encoderUnavailable(format)
        }
        let animated = frames.count > 1
        if animated {
            switch format {
            case .gif:
                CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: options.loopCount]] as CFDictionary)
            case .png:
                CGImageDestinationSetProperties(destination, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: options.loopCount]] as CFDictionary)
            default:
                break
            }
        }

        for (index, frame) in frames.enumerated() {
            var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
            switch format {
            case .jpeg:
                properties[kCGImageDestinationLossyCompressionQuality] = Double(options.quality) / 100
                if options.progressiveJPEG {
                    properties[kCGImagePropertyJFIFDictionary] = [kCGImagePropertyJFIFIsProgressive: true]
                }
            case .avif:
                let quality = options.lossless ? maximumAVIFQuality : min(maximumAVIFQuality, Double(options.quality) / 100)
                properties[kCGImageDestinationLossyCompressionQuality] = quality
            case .heic:
                properties[kCGImageDestinationLossyCompressionQuality] = options.lossless ? 1.0 : Double(options.quality) / 100
            case .gif:
                if animated {
                    let delay = index < options.frameDelays.count ? options.frameDelays[index] : 0.1
                    properties[kCGImagePropertyGIFDictionary] = [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]
                }
            case .png:
                if animated {
                    let delay = index < options.frameDelays.count ? options.frameDelays[index] : 0.1
                    properties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyAPNGDelayTime: delay, kCGImagePropertyAPNGUnclampedDelayTime: delay]
                }
            case .webp:
                break
            }
            if index == 0, let metadata {
                CGImageDestinationAddImageAndMetadata(destination, frame, metadata, properties as CFDictionary)
            } else {
                CGImageDestinationAddImage(destination, frame, properties as CFDictionary)
            }
        }
        guard CGImageDestinationFinalize(destination) else {
            throw OptimizerError.encodingFailed(format, "The system encoder rejected the image.")
        }
        if format == .avif && options.lossless { notes.append("AVIF has no lossless mode here; quality 99 used.") }
        if animated { notes.append("Animated \(format.displayName) with \(frames.count) frames.") }
        return output as Data
    }
}

/// Opens a written file and decodes a tiny version of it to prove it is readable.
public enum OutputValidator {
    public static func validate(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                kCGImageSourceThumbnailMaxPixelSize: 16] as CFDictionary) != nil else {
            throw OptimizerError.outputValidationFailed(url)
        }
    }

    public static func validate(data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else { return false }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                 kCGImageSourceThumbnailMaxPixelSize: 16] as CFDictionary) != nil
    }
}
