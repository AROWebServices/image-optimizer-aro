import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import OptimizerCore

/// Generates deterministic sample images so the suite needs no binary fixtures.
/// To test with real photos, drop files into a folder and point `TestImages.externalSamples` at it.
enum TestImages {
    static let externalSamples: URL? = ProcessInfo.processInfo.environment["OPTIMIZER_SAMPLE_DIR"].map { URL(fileURLWithPath: $0) }

    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func temporaryDirectory(_ name: String = "OptimizerCoreTests") -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    struct LCG {
        var state: UInt64
        mutating func next() -> UInt8 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return UInt8(truncatingIfNeeded: state >> 33)
        }
    }

    static func context(width: Int, height: Int, alpha: Bool, colorSpace: CGColorSpace = sRGB) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                  bitmapInfo: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
    }

    /// Smooth gradients plus noise: tens of thousands of colours, like a photograph.
    static func photo(width: Int = 640, height: Int = 480, colorSpace: CGColorSpace = sRGB, seed: UInt64 = 1) -> CGImage {
        let ctx = context(width: width, height: height, alpha: false, colorSpace: colorSpace)
        var rng = LCG(state: seed)
        let bytesPerRow = ctx.bytesPerRow
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * bytesPerRow + x * 4
                let noise = Int(rng.next() % 24)
                data[i] = UInt8(min(255, (x * 255) / max(1, width) + noise))
                data[i + 1] = UInt8(min(255, (y * 255) / max(1, height) + noise))
                data[i + 2] = UInt8(min(255, ((x + y) * 127) / max(1, width + height) + noise))
                data[i + 3] = 255
            }
        }
        return ctx.makeImage()!
    }

    /// Flat colour blocks and stripes, like a screenshot or logo.
    static func graphic(width: Int = 400, height: Int = 300, colors: Int = 6, alpha: Bool = false) -> CGImage {
        let ctx = context(width: width, height: height, alpha: alpha)
        if alpha { ctx.clear(CGRect(x: 0, y: 0, width: width, height: height)) } else {
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let palette: [CGColor] = (0..<colors).map { i in
            CGColor(red: CGFloat((i * 37) % 255) / 255, green: CGFloat((i * 91) % 255) / 255, blue: CGFloat((i * 173) % 255) / 255, alpha: 1)
        }
        let band = max(1, height / colors)
        for (i, color) in palette.enumerated() {
            ctx.setFillColor(color)
            ctx.fill(CGRect(x: alpha ? width / 4 : 0, y: i * band, width: alpha ? width / 2 : width, height: band))
        }
        return ctx.makeImage()!
    }

    /// Photographic content with a transparent circle cut-out.
    static func transparentPhoto(width: Int = 320, height: Int = 320) -> CGImage {
        let ctx = context(width: width, height: height, alpha: true)
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.addEllipse(in: CGRect(x: 20, y: 20, width: width - 40, height: height - 40))
        ctx.clip()
        ctx.draw(photo(width: width, height: height, seed: 7), in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    @discardableResult
    static func write(_ image: CGImage, type: UTType, to url: URL, properties: [CFString: Any] = [:]) -> URL {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        precondition(CGImageDestinationFinalize(destination), "could not write \(url.lastPathComponent)")
        return url
    }

    static func writeAnimatedGIF(frames: Int = 4, size: Int = 96, to url: URL) -> URL {
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil)!
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for i in 0..<frames {
            let ctx = context(width: size, height: size, alpha: false)
            ctx.setFillColor(CGColor(red: CGFloat(i) / CGFloat(frames), green: 0.3, blue: 0.6, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: i * 10, y: 10, width: 20, height: 20))
            CGImageDestinationAddImage(destination, ctx.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.08]] as CFDictionary)
        }
        precondition(CGImageDestinationFinalize(destination))
        return url
    }

    /// A landscape bitmap tagged with orientation 6 (rotate 90° CW), so the upright image is portrait.
    static func writeOrientedJPEG(to url: URL, width: Int = 400, height: Int = 200, withGPS: Bool = true, artist: String? = "Test Artist") -> URL {
        var properties: [CFString: Any] = [
            kCGImagePropertyOrientation: 6,
            kCGImageDestinationLossyCompressionQuality: 0.9,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2024:06:01 12:00:00", kCGImagePropertyExifLensModel: "Test Lens 50mm"]
        ]
        var tiff: [CFString: Any] = [kCGImagePropertyTIFFOrientation: 6, kCGImagePropertyTIFFMake: "TestCam"]
        if let artist {
            tiff[kCGImagePropertyTIFFArtist] = artist
            tiff[kCGImagePropertyTIFFCopyright] = "© \(artist)"
        }
        properties[kCGImagePropertyTIFFDictionary] = tiff
        if withGPS {
            properties[kCGImagePropertyGPSDictionary] = [
                kCGImagePropertyGPSLatitude: 48.8584, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 2.2945, kCGImagePropertyGPSLongitudeRef: "E"
            ]
        }
        return write(photo(width: width, height: height, seed: 3), type: .jpeg, to: url, properties: properties)
    }

    static func writeP3PNG(to url: URL) -> URL {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        return write(photo(width: 200, height: 150, colorSpace: p3, seed: 9), type: .png, to: url)
    }

    static func writeCorrupted(to url: URL) -> URL {
        var bytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0]
        var rng = LCG(state: 42)
        for _ in 0..<2000 { bytes.append(rng.next()) }
        try! Data(bytes).write(to: url)
        return url
    }

    static func writeSVG(to url: URL) -> URL {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" viewBox="0 0 120 80">
          <rect width="120" height="80" fill="#2a6df4"/>
          <circle cx="60" cy="40" r="25" fill="#ffffff"/>
        </svg>
        """
        try! svg.data(using: .utf8)!.write(to: url)
        return url
    }

    static func analysis(_ url: URL) throws -> ImageAnalysis {
        try ImageAnalyzer().analyze(url: url)
    }

    static func job(_ url: URL, root: URL? = nil) throws -> ProcessingJob {
        ProcessingJob(sourceURL: url, importRoot: root, analysis: try analysis(url))
    }

    static func properties(of url: URL) -> [CFString: Any] {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
    }

    static func properties(of data: Data) -> [CFString: Any] {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
    }

    static func decode(_ data: Data) -> CGImage {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCreateImageAtIndex(source, 0, nil)!
    }

    static func frameCount(_ url: URL) -> Int {
        CGImageSourceGetCount(CGImageSourceCreateWithURL(url as CFURL, nil)!)
    }

    /// RGBA pixel at (x, y), straight alpha, in sRGB.
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let ctx = context(width: image.width, height: image.height, alpha: true)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let i = y * ctx.bytesPerRow + x * 4
        let a = Int(data[i + 3])
        func straight(_ v: UInt8) -> Int { a == 0 ? 0 : min(255, Int(v) * 255 / a) }
        return (straight(data[i]), straight(data[i + 1]), straight(data[i + 2]), a)
    }

    static func sha256(_ url: URL) -> Data {
        // Simple content fingerprint without CryptoKit: size + sampled bytes + full hash via Hasher is enough for change detection.
        let data = try! Data(contentsOf: url)
        var hasher = Hasher()
        hasher.combine(data)
        return withUnsafeBytes(of: hasher.finalize()) { Data($0) } + Data([UInt8(data.count & 0xff)])
    }
}
