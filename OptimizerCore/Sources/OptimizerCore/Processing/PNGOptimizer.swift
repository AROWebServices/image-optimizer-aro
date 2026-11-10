import Foundation
import CoreGraphics

/// Lossless PNG size reductions: drop an unused alpha channel and switch to an indexed palette
/// when the image has 256 colours or fewer. Pixel values never change.
public enum PNGOptimizer {
    public struct Outcome {
        public var image: CGImage
        public var note: String?
    }

    public static func optimize(_ image: CGImage, allowPalette: Bool) -> Outcome {
        let colorSpace: CGColorSpace = {
            if let space = image.colorSpace, space.model == .rgb { return space }
            return CGColorSpace(name: CGColorSpace.sRGB)!
        }()
        guard image.bitsPerComponent <= 8, let buffer = try? PixelBuffer(image: image, colorSpace: colorSpace) else {
            return Outcome(image: image, note: nil)
        }
        let opaque = buffer.isOpaque

        if allowPalette && opaque, let colors = buffer.uniqueColors(limit: 256), let indexed = indexedImage(buffer: buffer, colors: colors) {
            return Outcome(image: indexed, note: "PNG stored with a \(colors.count)-colour palette (lossless).")
        }
        if opaque && image.alphaInfo != .none && image.alphaInfo != .noneSkipLast && image.alphaInfo != .noneSkipFirst {
            if let rgb = opaqueImage(buffer: buffer) {
                return Outcome(image: rgb, note: "Unused alpha channel removed from PNG.")
            }
        }
        return Outcome(image: image, note: nil)
    }

    static func indexedImage(buffer: PixelBuffer, colors: [UInt32]) -> CGImage? {
        guard !colors.isEmpty, colors.count <= 256 else { return nil }
        var table = [UInt8](repeating: 0, count: colors.count * 3)
        var lookup = [UInt32: UInt8]()
        for (i, color) in colors.enumerated() {
            table[i * 3] = UInt8((color >> 24) & 0xff)
            table[i * 3 + 1] = UInt8((color >> 16) & 0xff)
            table[i * 3 + 2] = UInt8((color >> 8) & 0xff)
            lookup[color] = UInt8(i)
        }
        var indices = [UInt8](repeating: 0, count: buffer.width * buffer.height)
        var p = 0
        for i in 0..<indices.count {
            let key = UInt32(buffer.bytes[p]) << 24 | UInt32(buffer.bytes[p + 1]) << 16 | UInt32(buffer.bytes[p + 2]) << 8 | UInt32(buffer.bytes[p + 3])
            indices[i] = lookup[key] ?? 0
            p += 4
        }
        guard let indexedSpace = CGColorSpace(indexedBaseSpace: buffer.colorSpace, last: colors.count - 1, colorTable: table),
              let provider = CGDataProvider(data: Data(indices) as CFData) else { return nil }
        return CGImage(width: buffer.width, height: buffer.height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: buffer.width,
                       space: indexedSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    static func opaqueImage(buffer: PixelBuffer) -> CGImage? {
        guard let context = CGContext(data: nil, width: buffer.width, height: buffer.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: buffer.colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let provider = CGDataProvider(data: Data(buffer.bytes) as CFData),
              let source = CGImage(width: buffer.width, height: buffer.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: buffer.bytesPerRow,
                                   space: buffer.colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        context.interpolationQuality = .none
        context.draw(source, in: CGRect(x: 0, y: 0, width: buffer.width, height: buffer.height))
        return context.makeImage()
    }
}
