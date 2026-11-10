import Foundation

/// Concrete encoders the app can write.
public enum OutputFormat: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case webp, avif, jpeg, png, heic, gif

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .webp: return "WebP"
        case .avif: return "AVIF"
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .gif: return "GIF"
        }
    }

    public var fileExtension: String {
        switch self {
        case .webp: return "webp"
        case .avif: return "avif"
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .gif: return "gif"
        }
    }

    public var utTypeIdentifier: String {
        switch self {
        case .webp: return "org.webmproject.webp"
        case .avif: return "public.avif"
        case .jpeg: return "public.jpeg"
        case .png: return "public.png"
        case .heic: return "public.heic"
        case .gif: return "com.compuserve.gif"
        }
    }

    public var imageFormat: ImageFormat {
        switch self {
        case .webp: return .webp
        case .avif: return .avif
        case .jpeg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        case .gif: return .gif
        }
    }

    public var supportsTransparency: Bool { self != .jpeg }

    /// Formats this app can write as a multi-frame animation.
    public var supportsAnimation: Bool {
        switch self {
        case .gif, .png, .webp: return true
        default: return false
        }
    }

    /// Formats that offer a true lossless mode.
    public var supportsLossless: Bool {
        switch self {
        case .webp, .png: return true
        default: return false
        }
    }

    /// Whether a 1–100 quality value has a meaning for this encoder.
    public var usesQualitySlider: Bool {
        switch self {
        case .webp, .avif, .jpeg, .heic: return true
        case .png, .gif: return false
        }
    }

    public var recommendedUse: String {
        switch self {
        case .webp: return "Recommended default for most websites. Lossy or lossless, keeps transparency, supported by every modern browser."
        case .avif: return "Smallest files for photos. Keeps transparency. Browser support is good but older browsers cannot display it."
        case .jpeg: return "Best for photographs that do not need transparency and must open everywhere."
        case .png: return "Lossless. Best for graphics, screenshots, icons and anything that needs exact pixels or transparency."
        case .heic: return "Apple-focused workflows only. Not displayed by most web browsers."
        case .gif: return "Legacy format. Only useful for keeping existing GIF animations; 256 colours maximum."
        }
    }

    /// What the quality percentage means for this encoder. Shown in the UI.
    public var qualityExplanation: String {
        switch self {
        case .webp: return "WebP quality 80 looks like JPEG quality 85–90 at a smaller size. Below 60 artifacts appear in gradients and text."
        case .avif: return "AVIF quality is a different scale again: 60–70 already matches JPEG 85. Values above 90 give little benefit. 100 is not lossless."
        case .jpeg: return "JPEG quality follows the familiar libjpeg scale. 80–85 is the sweet spot for web photos; below 70 blocking becomes visible."
        case .heic: return "HEIC uses the HEVC scale; 70–80 matches JPEG 85–90."
        case .png: return "PNG is always lossless. Optimisation reduces the palette and strips metadata instead of using a quality value."
        case .gif: return "GIF is palette-based. Frames are re-encoded losslessly within 256 colours; there is no quality value."
        }
    }
}

/// What the user picked in the Format section.
public enum FormatSelection: String, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case auto, original, webp, avif, jpeg, png, heic, gif

    public var id: String { rawValue }

    public var fixedFormat: OutputFormat? {
        switch self {
        case .auto, .original: return nil
        case .webp: return .webp
        case .avif: return .avif
        case .jpeg: return .jpeg
        case .png: return .png
        case .heic: return .heic
        case .gif: return .gif
        }
    }

    public var displayName: String {
        switch self {
        case .auto: return "Auto (best for web)"
        case .original: return "Same as original"
        default: return fixedFormat?.displayName ?? rawValue
        }
    }

    public var summary: String {
        switch self {
        case .auto: return "Picks WebP, AVIF, PNG or GIF per image based on content, transparency and animation. The choice is explained for each file."
        case .original: return "Keeps each file's current format and only recompresses and resizes."
        default: return fixedFormat?.recommendedUse ?? ""
        }
    }
}
