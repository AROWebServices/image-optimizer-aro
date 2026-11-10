import Foundation
import ImageIO
import CoreGraphics
import AppKit

/// Memory-friendly decoding. Images are decoded at the size they will be used at,
/// and EXIF orientation is applied during decode so every later stage sees upright pixels.
public enum ImageDecoder {
    public static func makeSource(url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw OptimizerError.unreadable(url)
        }
        guard CGImageSourceGetCount(source) > 0 else { throw OptimizerError.corrupted(url) }
        return source
    }

    public static func makeSource(data: Data) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else {
            throw OptimizerError.corrupted(URL(fileURLWithPath: "memory"))
        }
        return source
    }

    /// Decodes one frame, upright, with its longest side no larger than `maxPixelSize`
    /// (never enlarged). `nil` decodes at full resolution.
    public static func decodeFrame(_ source: CGImageSource, index: Int = 0, maxPixelSize: Int? = nil) throws -> CGImage {
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false
        ]
        if let maxPixelSize, maxPixelSize > 0 {
            options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
        } else if let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int {
            options[kCGImageSourceThumbnailMaxPixelSize] = max(width, height)
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else {
            throw OptimizerError.corrupted(URL(fileURLWithPath: "frame \(index)"))
        }
        return image
    }

    /// Per-frame delays in seconds for animated GIF, PNG, WebP and HEICS sources.
    public static func frameDelays(_ source: CGImageSource) -> [Double] {
        let count = CGImageSourceGetCount(source)
        return (0..<count).map { index in
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return 0.1 }
            let candidates: [(CFString, CFString, CFString)] = [
                (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
                (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
                (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
                (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime)
            ]
            for (dictionaryKey, unclampedKey, clampedKey) in candidates {
                if let dictionary = properties[dictionaryKey] as? [CFString: Any] {
                    let value = (dictionary[unclampedKey] as? Double) ?? (dictionary[clampedKey] as? Double) ?? 0.1
                    return value < 0.02 ? 0.1 : value
                }
            }
            return 0.1
        }
    }

    /// 0 means "loop forever".
    public static func loopCount(_ source: CGImageSource) -> Int {
        guard let properties = CGImageSourceCopyProperties(source, nil) as? [CFString: Any] else { return 0 }
        if let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any], let loops = gif[kCGImagePropertyGIFLoopCount] as? Int { return loops }
        if let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any], let loops = png[kCGImagePropertyAPNGLoopCount] as? Int { return loops }
        if let webp = properties[kCGImagePropertyWebPDictionary] as? [CFString: Any], let loops = webp[kCGImagePropertyWebPLoopCount] as? Int { return loops }
        return 0
    }

    /// Copies the embedded ICC profile of a colour space, if it has one and it is not sRGB.
    public static func iccProfile(for colorSpace: CGColorSpace?) -> Data? {
        guard let colorSpace, colorSpace.name != CGColorSpace.sRGB else { return nil }
        return colorSpace.copyICCData() as Data?
    }
}

/// Renders SVG files with AppKit, which has supported SVG since macOS 11.
public enum SVGRasterizer {
    public static func intrinsicSize(of url: URL) -> PixelSize? {
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else { return nil }
        return PixelSize(width: Int(image.size.width.rounded()), height: Int(image.size.height.rounded()))
    }

    public static func rasterize(url: URL, size: PixelSize) throws -> CGImage {
        guard let image = NSImage(contentsOf: url), image.isValid else { throw OptimizerError.unreadable(url) }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: max(1, size.width), height: max(1, size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw OptimizerError.encodingFailed(.png, "Could not create a drawing context for the SVG.")
        }
        context.interpolationQuality = .high
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        image.draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        guard let result = context.makeImage() else { throw OptimizerError.corrupted(url) }
        return result
    }
}
