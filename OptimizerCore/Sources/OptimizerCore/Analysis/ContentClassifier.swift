import Foundation
import CoreGraphics

/// Looks at a small sample of an image and decides whether it is photographic or flat graphics,
/// how many colours it uses and whether its alpha channel is actually used.
public enum ContentClassifier {
    public struct Sample: Sendable, Hashable {
        public var contentKind: ContentKind
        public var uniqueColors: Int
        public var transparentFraction: Double
        public var flatRunFraction: Double

        public var usesTransparency: Bool { transparentFraction > 0.0005 }
    }

    public static let uniqueColorCap = 100_000

    /// `image` should already be small (≤ 512 px) — the caller decodes a thumbnail.
    public static func classify(_ image: CGImage, hintLossyPhotoFormat: Bool) -> Sample {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else {
            return Sample(contentKind: .photo, uniqueColors: 0, transparentFraction: 0, flatRunFraction: 0)
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow, space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drew else {
            return Sample(contentKind: .photo, uniqueColors: 0, transparentFraction: 0, flatRunFraction: 0)
        }

        var exactColors = Set<UInt32>()
        var transparent = 0
        var flatRuns = 0
        var comparisons = 0
        let total = width * height
        for y in 0..<height {
            let row = y * bytesPerRow
            var previous: UInt32 = 0
            for x in 0..<width {
                let i = row + x * 4
                let r = UInt32(pixels[i]), g = UInt32(pixels[i + 1]), b = UInt32(pixels[i + 2]), a = UInt32(pixels[i + 3])
                if a < 250 { transparent += 1 }
                let key = (r << 24) | (g << 16) | (b << 8) | a
                if exactColors.count < uniqueColorCap { exactColors.insert(key) }
                if x > 0 {
                    comparisons += 1
                    if key == previous { flatRuns += 1 }
                }
                previous = key
            }
        }

        let unique = exactColors.count
        let uniqueRatio = Double(unique) / Double(total)
        let flatFraction = comparisons > 0 ? Double(flatRuns) / Double(comparisons) : 0
        let transparentFraction = Double(transparent) / Double(total)

        // Photographs have tens of thousands of distinct colours and almost no identical neighbours.
        // Screenshots, logos and diagrams have large flat areas and comparatively few colours.
        let kind: ContentKind
        if unique <= 256 {
            kind = .graphic
        } else if flatFraction > 0.45 {
            kind = .graphic
        } else if uniqueRatio < 0.08 && flatFraction > 0.2 {
            kind = .graphic
        } else if hintLossyPhotoFormat && flatFraction < 0.6 {
            kind = .photo
        } else {
            kind = .photo
        }
        return Sample(contentKind: kind, uniqueColors: unique, transparentFraction: transparentFraction, flatRunFraction: flatFraction)
    }
}
