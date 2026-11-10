import Foundation

public enum ContentKind: String, Codable, Sendable {
    /// Continuous-tone content: photographs, renders, paintings.
    case photo
    /// Flat colours, text, UI: screenshots, logos, diagrams.
    case graphic

    public var displayName: String {
        switch self {
        case .photo: return "Photo"
        case .graphic: return "Graphic"
        }
    }
}

/// Everything the app learns about a source file before processing it.
public struct ImageAnalysis: Codable, Hashable, Sendable {
    public var url: URL
    public var fileSize: Int64
    public var format: ImageFormat
    public var utTypeIdentifier: String
    /// Dimensions after applying the EXIF orientation.
    public var pixelSize: PixelSize
    /// Dimensions as stored in the file.
    public var storedPixelSize: PixelSize
    public var orientation: Int
    public var bitDepth: Int
    public var hasAlphaChannel: Bool
    /// True when at least some pixels are actually not fully opaque.
    public var usesTransparency: Bool
    public var isAnimated: Bool
    public var frameCount: Int
    public var colorSpaceName: String?
    public var isSRGB: Bool
    public var hasEXIF: Bool
    public var hasGPS: Bool
    public var contentKind: ContentKind
    /// Distinct colours found in a 256 px sample. Capped at 100 000.
    public var uniqueColorEstimate: Int
    /// Compressed bits per pixel of the source file.
    public var bitsPerPixel: Double

    public init(url: URL, fileSize: Int64, format: ImageFormat, utTypeIdentifier: String,
                pixelSize: PixelSize, storedPixelSize: PixelSize, orientation: Int, bitDepth: Int,
                hasAlphaChannel: Bool, usesTransparency: Bool, isAnimated: Bool, frameCount: Int,
                colorSpaceName: String?, isSRGB: Bool, hasEXIF: Bool, hasGPS: Bool,
                contentKind: ContentKind, uniqueColorEstimate: Int, bitsPerPixel: Double) {
        self.url = url
        self.fileSize = fileSize
        self.format = format
        self.utTypeIdentifier = utTypeIdentifier
        self.pixelSize = pixelSize
        self.storedPixelSize = storedPixelSize
        self.orientation = orientation
        self.bitDepth = bitDepth
        self.hasAlphaChannel = hasAlphaChannel
        self.usesTransparency = usesTransparency
        self.isAnimated = isAnimated
        self.frameCount = frameCount
        self.colorSpaceName = colorSpaceName
        self.isSRGB = isSRGB
        self.hasEXIF = hasEXIF
        self.hasGPS = hasGPS
        self.contentKind = contentKind
        self.uniqueColorEstimate = uniqueColorEstimate
        self.bitsPerPixel = bitsPerPixel
    }

    public var isOriented: Bool { orientation > 1 }

    /// Heuristic: a lossy file this small per pixel has already been compressed hard.
    public var isLikelyAlreadyCompressed: Bool {
        switch format {
        case .jpeg: return bitsPerPixel < 1.6
        case .webp, .avif, .heic, .heif: return bitsPerPixel < 1.0
        default: return false
        }
    }

    /// Number of colours small enough for an indexed PNG.
    public var isPaletteCandidate: Bool { uniqueColorEstimate <= 256 && !usesTransparency }
}
