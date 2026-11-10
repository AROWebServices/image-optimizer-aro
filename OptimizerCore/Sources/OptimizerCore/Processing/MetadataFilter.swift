import Foundation
import ImageIO

/// Builds the metadata block written into the output according to the user's policy.
public enum MetadataFilter {
    /// XMP paths that count as "copyright and author" information.
    public static let copyrightTagPaths: [String] = [
        "tiff:Artist", "tiff:Copyright",
        "dc:creator", "dc:rights",
        "xmpRights:Marked", "xmpRights:WebStatement", "xmpRights:UsageTerms", "xmpRights:Owner",
        "photoshop:Credit", "photoshop:AuthorsPosition", "photoshop:Source",
        "Iptc4xmpCore:CreatorContactInfo"
    ]

    /// Returns the metadata to embed, or nil when the policy removes everything.
    public static func destinationMetadata(from source: CGImageSource, index: Int = 0,
                                           settings: MetadataSettings, outputSize: PixelSize) -> CGImageMetadata? {
        switch settings.policy {
        case .removeAll, .colorProfileOnly:
            return nil
        case .keepAll:
            guard let original = CGImageSourceCopyMetadataAtIndex(source, index, nil),
                  let mutable = CGImageMetadataCreateMutableCopy(original) else { return nil }
            if settings.stripGPS { removeGPS(from: mutable) }
            normalizeOrientation(in: mutable, outputSize: outputSize)
            return mutable
        case .copyrightOnly:
            guard let original = CGImageSourceCopyMetadataAtIndex(source, index, nil) else { return nil }
            let mutable = CGImageMetadataCreateMutable()
            var copied = 0
            for path in copyrightTagPaths {
                if let tag = CGImageMetadataCopyTagWithPath(original, nil, path as CFString) {
                    if CGImageMetadataSetTagWithPath(mutable, nil, path as CFString, tag) { copied += 1 }
                }
            }
            return copied > 0 ? mutable : nil
        }
    }

    public static func removeGPS(from metadata: CGMutableImageMetadata) {
        var paths: [String] = []
        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, [kCGImageMetadataEnumerateRecursively: false] as CFDictionary) { path, _ in
            let string = path as String
            if string.hasPrefix("exif:GPS") || string.lowercased().contains("gps") { paths.append(string) }
            return true
        }
        for path in paths {
            CGImageMetadataRemoveTagWithPath(metadata, nil, path as CFString)
        }
    }

    /// Pixels are written upright, so the stored orientation must say "normal" and the
    /// EXIF pixel dimensions must describe the new size.
    static func normalizeOrientation(in metadata: CGMutableImageMetadata, outputSize: PixelSize) {
        CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyTIFFDictionary, kCGImagePropertyTIFFOrientation, 1 as CFNumber)
        if CGImageMetadataCopyTagMatchingImageProperty(metadata, kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelXDimension) != nil {
            CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelXDimension, outputSize.width as CFNumber)
            CGImageMetadataSetValueMatchingImageProperty(metadata, kCGImagePropertyExifDictionary, kCGImagePropertyExifPixelYDimension, outputSize.height as CFNumber)
        }
    }

    /// Serialises metadata as an XMP packet (used for WebP, which stores XMP but not EXIF).
    public static func xmpData(_ metadata: CGImageMetadata) -> Data? {
        CGImageMetadataCreateXMPData(metadata, nil) as Data?
    }

    /// True when the metadata block has at least one tag.
    public static func isEmpty(_ metadata: CGImageMetadata) -> Bool {
        var count = 0
        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, [kCGImageMetadataEnumerateRecursively: false] as CFDictionary) { _, _ in
            count += 1
            return false
        }
        return count == 0
    }
}
