import Foundation

public enum MetadataPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case removeAll, colorProfileOnly, copyrightOnly, keepAll

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .removeAll: return "Remove all metadata"
        case .colorProfileOnly: return "Keep color profile only"
        case .copyrightOnly: return "Keep copyright and author only"
        case .keepAll: return "Keep all metadata"
        }
    }

    public var explanation: String {
        switch self {
        case .removeAll:
            return "Strips EXIF, IPTC, XMP and location data. Colors are converted to sRGB, which browsers assume, so no profile is needed."
        case .colorProfileOnly:
            return "Strips EXIF, IPTC, XMP and location data but embeds the color profile so colors are displayed exactly as intended."
        case .copyrightOnly:
            return "Keeps the artist, creator and copyright fields plus the color profile. Everything else, including camera and location data, is removed."
        case .keepAll:
            return "Keeps every tag the encoder can store, including camera settings and dates. GPS location is still removed unless you turn that off."
        }
    }
}

public struct MetadataSettings: Codable, Hashable, Sendable {
    public var policy: MetadataPolicy
    /// Convert wide-gamut or unusual profiles to sRGB for predictable web display.
    public var convertToSRGB: Bool
    /// Applies to `.keepAll`: still strip GPS tags.
    public var stripGPS: Bool

    public init(policy: MetadataPolicy = .colorProfileOnly, convertToSRGB: Bool = true, stripGPS: Bool = true) {
        self.policy = policy
        self.convertToSRGB = convertToSRGB
        self.stripGPS = stripGPS
    }

    /// `.removeAll` always converts to sRGB; otherwise there would be no profile to describe the colors.
    public var effectiveConvertToSRGB: Bool { policy == .removeAll || convertToSRGB }

    public static let colorExplanation = "Images in Display P3, Adobe RGB or ProPhoto are converted to sRGB with the system color engine so they look the same in browsers that ignore profiles. Turn this off to keep the original profile embedded."
}
