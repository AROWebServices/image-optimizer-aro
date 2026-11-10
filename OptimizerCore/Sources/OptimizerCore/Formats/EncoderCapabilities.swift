import Foundation
import ImageIO
import libwebp

/// Which encoders exist on this Mac. ImageIO decides for AVIF and HEIC; WebP is always
/// available because libwebp is compiled into the app.
public struct EncoderCapabilities: Sendable, Hashable {
    public var canEncodeAVIF: Bool
    public var canEncodeHEIC: Bool
    public var canEncodeWebP: Bool
    public var canDecodeWebP: Bool
    public var canDecodeAVIF: Bool
    public var webpVersion: String

    public init(canEncodeAVIF: Bool, canEncodeHEIC: Bool, canEncodeWebP: Bool = true,
                canDecodeWebP: Bool, canDecodeAVIF: Bool, webpVersion: String) {
        self.canEncodeAVIF = canEncodeAVIF
        self.canEncodeHEIC = canEncodeHEIC
        self.canEncodeWebP = canEncodeWebP
        self.canDecodeWebP = canDecodeWebP
        self.canDecodeAVIF = canDecodeAVIF
        self.webpVersion = webpVersion
    }

    public static let current: EncoderCapabilities = {
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        let readable = (CGImageSourceCopyTypeIdentifiers() as? [String]) ?? []
        let version = Int(WebPGetEncoderVersion())
        let versionString = "\((version >> 16) & 0xff).\((version >> 8) & 0xff).\(version & 0xff)"
        return EncoderCapabilities(canEncodeAVIF: writable.contains("public.avif"),
                                   canEncodeHEIC: writable.contains("public.heic"),
                                   canEncodeWebP: true,
                                   canDecodeWebP: readable.contains("org.webmproject.webp"),
                                   canDecodeAVIF: readable.contains("public.avif"),
                                   webpVersion: versionString)
    }()

    /// A configuration with every encoder available, for tests and previews.
    public static let all = EncoderCapabilities(canEncodeAVIF: true, canEncodeHEIC: true, canDecodeWebP: true, canDecodeAVIF: true, webpVersion: "test")

    public func supports(_ format: OutputFormat) -> Bool {
        switch format {
        case .webp: return canEncodeWebP
        case .avif: return canEncodeAVIF
        case .heic: return canEncodeHEIC
        case .jpeg, .png, .gif: return true
        }
    }

    public func encoderDescription(for format: OutputFormat) -> String {
        switch format {
        case .webp: return "Bundled libwebp \(webpVersion)"
        case .avif: return canEncodeAVIF ? "System encoder (ImageIO)" : "Not available on this Mac (needs macOS 14 or later)"
        case .heic: return canEncodeHEIC ? "System encoder (ImageIO)" : "Not available on this Mac"
        case .jpeg, .png, .gif: return "System encoder (ImageIO)"
        }
    }
}
