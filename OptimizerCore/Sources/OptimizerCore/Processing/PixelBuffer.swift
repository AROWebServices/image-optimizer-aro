import Foundation
import CoreGraphics
import Accelerate

/// 8-bit RGBA pixels of an image, straight (non-premultiplied) alpha.
struct PixelBuffer {
    var width: Int
    var height: Int
    var bytesPerRow: Int
    var bytes: [UInt8]
    var colorSpace: CGColorSpace

    /// Draws the image into an RGBA bitmap in `colorSpace` and un-premultiplies the alpha.
    init(image: CGImage, colorSpace: CGColorSpace) throws {
        width = image.width
        height = image.height
        bytesPerRow = width * 4
        self.colorSpace = colorSpace
        bytes = [UInt8](repeating: 0, count: bytesPerRow * height)
        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow, space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var buffer = vImage_Buffer(data: raw.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
            return vImageUnpremultiplyData_RGBA8888(&buffer, &buffer, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        }
        guard ok else { throw OptimizerError.encodingFailed(.webp, "Could not read the image pixels.") }
    }

    var isOpaque: Bool {
        var index = 3
        let count = bytes.count
        while index < count {
            if bytes[index] != 255 { return false }
            index += 4
        }
        return true
    }

    /// Distinct RGBA values, or nil as soon as there are more than `limit`.
    func uniqueColors(limit: Int) -> [UInt32]? {
        var seen = Set<UInt32>()
        var ordered: [UInt32] = []
        var index = 0
        let count = bytes.count
        while index < count {
            let key = UInt32(bytes[index]) << 24 | UInt32(bytes[index + 1]) << 16 | UInt32(bytes[index + 2]) << 8 | UInt32(bytes[index + 3])
            if seen.insert(key).inserted {
                ordered.append(key)
                if ordered.count > limit { return nil }
            }
            index += 4
        }
        return ordered
    }
}
