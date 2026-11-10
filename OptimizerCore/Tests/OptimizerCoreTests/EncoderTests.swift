import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import OptimizerCore

@Suite("Encoders")
struct EncoderTests {
    let caps = EncoderCapabilities.current

    func encode(_ image: CGImage, _ format: OutputFormat, quality: Int = 80, lossless: Bool = false, progressive: Bool = true) throws -> Data {
        try ImageEncoder.encode(frames: [image], options: EncodeOptions(format: format, quality: quality, lossless: lossless, progressiveJPEG: progressive), metadata: nil).data
    }

    @Test(arguments: [OutputFormat.webp, .jpeg, .png, .gif, .avif, .heic])
    func roundTripOpensWithCorrectSize(format: OutputFormat) throws {
        guard caps.supports(format) else { return }
        let image = TestImages.photo(width: 120, height: 90)
        let data = try encode(image, format)
        #expect(OutputValidator.validate(data: data))
        let decoded = TestImages.decode(data)
        #expect(decoded.width == 120 && decoded.height == 90)
        let type = CGImageSourceGetType(CGImageSourceCreateWithData(data as CFData, nil)!)! as String
        #expect(ImageFormat(utTypeIdentifier: type) == format.imageFormat)
    }

    @Test(arguments: [OutputFormat.webp, .png, .avif, .heic])
    func transparencyIsPreserved(format: OutputFormat) throws {
        guard caps.supports(format) else { return }
        let data = try encode(TestImages.transparentPhoto(width: 128, height: 128), format)
        let decoded = TestImages.decode(data)
        #expect(TestImages.pixel(decoded, x: 2, y: 2).a == 0)
        #expect(TestImages.pixel(decoded, x: 64, y: 64).a == 255)
    }

    @Test func webpLosslessIsExact() throws {
        let image = TestImages.graphic(width: 64, height: 48, colors: 9, alpha: true)
        let data = try encode(image, .webp, lossless: true)
        let decoded = TestImages.decode(data)
        for (x, y) in [(5, 5), (32, 24), (60, 40), (20, 10)] {
            let a = TestImages.pixel(image, x: x, y: y)
            let b = TestImages.pixel(decoded, x: x, y: y)
            #expect(a == b, "pixel \(x),\(y)")
        }
    }

    @Test func lowerQualityGivesSmallerFiles() throws {
        let image = TestImages.photo(width: 400, height: 300)
        for format in [OutputFormat.webp, .jpeg, .avif, .heic] where caps.supports(format) {
            let low = try encode(image, format, quality: 40).count
            let high = try encode(image, format, quality: 92).count
            #expect(low < high, "\(format)")
        }
    }

    @Test func progressiveJPEGFlag() throws {
        let image = TestImages.photo(width: 200, height: 150)
        let progressive = try encode(image, .jpeg, progressive: true)
        let baseline = try encode(image, .jpeg, progressive: false)
        let jfif = TestImages.properties(of: progressive)[kCGImagePropertyJFIFDictionary] as? [CFString: Any]
        #expect(jfif?[kCGImagePropertyJFIFIsProgressive] as? Bool == true)
        let jfif2 = TestImages.properties(of: baseline)[kCGImagePropertyJFIFDictionary] as? [CFString: Any]
        #expect((jfif2?[kCGImagePropertyJFIFIsProgressive] as? Bool ?? false) == false)
    }

    @Test func pngPaletteOptimizationShrinksFlatGraphics() throws {
        let image = TestImages.graphic(width: 300, height: 200, colors: 8)
        let optimized = try ImageEncoder.encode(frames: [image], options: EncodeOptions(format: .png, quality: 100, lossless: true, optimizePNGPalette: true), metadata: nil)
        let plain = try ImageEncoder.encode(frames: [image], options: EncodeOptions(format: .png, quality: 100, lossless: true, optimizePNGPalette: false), metadata: nil)
        #expect(optimized.data.count < plain.data.count)
        #expect(optimized.notes.contains { $0.contains("palette") })
        let decoded = TestImages.decode(optimized.data)
        #expect(TestImages.pixel(decoded, x: 10, y: 10) == TestImages.pixel(image, x: 10, y: 10))
    }

    @Test func pngWithTransparencyIsNotPaletteReduced() throws {
        let image = TestImages.graphic(width: 100, height: 100, colors: 4, alpha: true)
        let result = try ImageEncoder.encode(frames: [image], options: EncodeOptions(format: .png, quality: 100, lossless: true), metadata: nil)
        #expect(!result.notes.contains { $0.contains("palette") })
        #expect(TestImages.pixel(TestImages.decode(result.data), x: 1, y: 1).a == 0)
    }

    @Test func jpegFlattensTransparencyToWhite() throws {
        let data = try encode(TestImages.transparentPhoto(width: 64, height: 64), .jpeg)
        let corner = TestImages.pixel(TestImages.decode(data), x: 1, y: 1)
        #expect(corner.a == 255)
    }

    @Test func animatedWebPKeepsFrames() throws {
        // Distinct frames: libwebp merges identical consecutive frames into one longer frame.
        let frames = (0..<3).map { i in TestImages.graphic(width: 50, height: 50, colors: 3 + i) }
        let data = try ImageEncoder.encode(frames: frames, options: EncodeOptions(format: .webp, quality: 80, lossless: false, frameDelays: [0.1, 0.1, 0.1], loopCount: 0), metadata: nil).data
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        #expect(CGImageSourceGetCount(source) == 3)
    }

    @Test func animatedGIFAndAPNGKeepFrames() throws {
        let frames = (0..<3).map { _ in TestImages.graphic(width: 50, height: 50, colors: 3) }
        for format in [OutputFormat.gif, .png] {
            let data = try ImageEncoder.encode(frames: frames, options: EncodeOptions(format: format, quality: 80, lossless: true, frameDelays: [0.1, 0.1, 0.1]), metadata: nil).data
            #expect(CGImageSourceGetCount(CGImageSourceCreateWithData(data as CFData, nil)!) == 3, "\(format)")
        }
    }

    @Test func avifRejectsNothingAtLosslessRequest() throws {
        guard caps.canEncodeAVIF else { return }
        let result = try ImageEncoder.encode(frames: [TestImages.photo(width: 64, height: 64)], options: EncodeOptions(format: .avif, quality: 100, lossless: true), metadata: nil)
        #expect(OutputValidator.validate(data: result.data))
        #expect(result.notes.contains { $0.contains("lossless") })
    }

    @Test func webpEmbedsICCProfile() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let image = TestImages.photo(width: 64, height: 64, colorSpace: p3)
        let data = try ImageEncoder.encode(frames: [image], options: EncodeOptions(format: .webp, quality: 80, lossless: false, iccProfile: p3.copyICCData() as Data?), metadata: nil).data
        let decoded = TestImages.decode(data)
        #expect(decoded.colorSpace?.name != CGColorSpace.sRGB)
        let plain = try encode(TestImages.photo(width: 64, height: 64), .webp)
        #expect(data.count > plain.count)
    }

    @Test func capabilitiesDescribeEncoders() {
        #expect(caps.canEncodeWebP)
        #expect(caps.encoderDescription(for: .webp).contains("libwebp"))
        #expect(caps.webpVersion.split(separator: ".").count == 3)
    }
}
