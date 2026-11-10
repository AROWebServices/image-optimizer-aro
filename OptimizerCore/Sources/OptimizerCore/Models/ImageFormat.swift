import Foundation
import UniformTypeIdentifiers

/// Container formats the app recognises as *input*.
public enum ImageFormat: String, Codable, CaseIterable, Sendable, Hashable {
    case jpeg, png, gif, webp, avif, heic, heif, tiff, bmp, svg, other

    public init(utTypeIdentifier: String) {
        switch utTypeIdentifier {
        case "public.jpeg": self = .jpeg
        case "public.png": self = .png
        case "com.compuserve.gif": self = .gif
        case "org.webmproject.webp", "public.webp": self = .webp
        case "public.avif", "public.avis": self = .avif
        case "public.heic", "public.heics": self = .heic
        case "public.heif", "public.heifs": self = .heif
        case "public.tiff": self = .tiff
        case "com.microsoft.bmp": self = .bmp
        case "public.svg-image": self = .svg
        default: self = .other
        }
    }

    public var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .gif: return "GIF"
        case .webp: return "WebP"
        case .avif: return "AVIF"
        case .heic: return "HEIC"
        case .heif: return "HEIF"
        case .tiff: return "TIFF"
        case .bmp: return "BMP"
        case .svg: return "SVG"
        case .other: return "Image"
        }
    }

    /// Formats whose containers can carry more than one frame as an animation.
    public var supportsAnimation: Bool {
        switch self {
        case .gif, .png, .webp, .avif, .heic, .heif: return true
        default: return false
        }
    }

    public var isLossy: Bool {
        switch self {
        case .jpeg, .avif, .heic, .heif, .webp: return true
        default: return false
        }
    }

    /// The output format that keeps the input container when the user chooses "Same as original".
    public var closestOutputFormat: OutputFormat {
        switch self {
        case .jpeg: return .jpeg
        case .png, .bmp, .tiff, .svg: return .png
        case .gif: return .gif
        case .webp: return .webp
        case .avif: return .avif
        case .heic, .heif: return .heic
        case .other: return .png
        }
    }

    /// Uniform types the import panel and drag-and-drop accept.
    public static let importableTypes: [UTType] = {
        var types: [UTType] = [.jpeg, .png, .gif, .webP, .heic, .heif, .tiff, .bmp, .svg]
        if let avif = UTType("public.avif") { types.append(avif) }
        // JFIF files are plain JPEGs with a different extension. macOS does not list "jfif" under
        // public.jpeg, so the open panel needs the (dynamic) type for that extension as well.
        for ext in jfifExtensions {
            if let type = UTType(filenameExtension: ext), !types.contains(type) { types.append(type) }
        }
        return types
    }()

    /// Extensions used for JPEG files in the JFIF container; decoded exactly like .jpg.
    public static let jfifExtensions: [String] = ["jfif", "jfi", "jif"]

    public static let importableExtensions: Set<String> = Set([
        "jpg", "jpeg", "jpe", "png", "gif", "webp", "heic", "heif", "hif", "tif", "tiff", "bmp", "svg", "avif"
    ] + jfifExtensions)
}
