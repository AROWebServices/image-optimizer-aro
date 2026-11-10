import Foundation

/// Chooses an output format for one image when the user asked for "Auto".
///
/// The strategy is a plain ordered list of rules so it is easy to read and change:
/// the first rule whose `matches` closure returns true wins.
public struct FormatSelector: Sendable {
    public struct Input: Sendable {
        public var analysis: ImageAnalysis
        public var capabilities: EncoderCapabilities
        /// AVIF may be chosen for photos.
        public var allowAVIF: Bool
        /// Only JPEG, PNG and GIF.
        public var compatibilityMode: Bool

        public init(analysis: ImageAnalysis, capabilities: EncoderCapabilities, allowAVIF: Bool, compatibilityMode: Bool) {
            self.analysis = analysis
            self.capabilities = capabilities
            self.allowAVIF = allowAVIF
            self.compatibilityMode = compatibilityMode
        }

        var avifAvailable: Bool { allowAVIF && capabilities.canEncodeAVIF && !compatibilityMode }
        var webpAvailable: Bool { capabilities.canEncodeWebP && !compatibilityMode }
    }

    public struct Decision: Sendable, Hashable {
        public var format: OutputFormat
        public var lossless: Bool
        public var reason: String

        public init(format: OutputFormat, lossless: Bool, reason: String) {
            self.format = format
            self.lossless = lossless
            self.reason = reason
        }
    }

    public struct Rule: Sendable {
        public var name: String
        public var matches: @Sendable (Input) -> Bool
        public var decide: @Sendable (Input) -> Decision

        public init(name: String, matches: @escaping @Sendable (Input) -> Bool, decide: @escaping @Sendable (Input) -> Decision) {
            self.name = name
            self.matches = matches
            self.decide = decide
        }
    }

    /// Ordered rules. Edit this table to change the strategy.
    public static let rules: [Rule] = [
        Rule(name: "Animated input keeps an animated container") { $0.analysis.isAnimated } decide: { input in
            let source = input.analysis.format
            if source == .gif && !input.webpAvailable {
                return Decision(format: .gif, lossless: true, reason: "Animated GIF kept as GIF so the animation survives (compatibility mode).")
            }
            if source == .png && input.compatibilityMode {
                return Decision(format: .png, lossless: true, reason: "Animated PNG kept as APNG so the animation survives.")
            }
            if input.webpAvailable {
                return Decision(format: .webp, lossless: false, reason: "Animated \(source.displayName) becomes animated WebP, which is far smaller and keeps every frame.")
            }
            return Decision(format: .gif, lossless: true, reason: "Animated image kept as GIF so the animation survives.")
        },
        Rule(name: "Vector graphics rasterize losslessly") { $0.analysis.format == .svg } decide: { input in
            if input.webpAvailable {
                return Decision(format: .webp, lossless: true, reason: "SVG rendered to lossless WebP so edges and text stay crisp.")
            }
            return Decision(format: .png, lossless: true, reason: "SVG rendered to PNG so edges and text stay crisp.")
        },
        Rule(name: "Graphics with transparency") { $0.analysis.contentKind == .graphic && $0.analysis.usesTransparency } decide: { input in
            if input.webpAvailable {
                return Decision(format: .webp, lossless: true, reason: "Flat graphic with transparency: lossless WebP keeps the alpha channel and is smaller than PNG.")
            }
            return Decision(format: .png, lossless: true, reason: "Flat graphic with transparency: PNG keeps the alpha channel losslessly.")
        },
        Rule(name: "Graphics, screenshots and text") { $0.analysis.contentKind == .graphic } decide: { input in
            if input.analysis.isPaletteCandidate {
                return Decision(format: .png, lossless: true, reason: "Only \(input.analysis.uniqueColorEstimate) colours: an indexed PNG is tiny and exact.")
            }
            if input.webpAvailable {
                return Decision(format: .webp, lossless: true, reason: "Screenshot or graphic: lossless WebP keeps text sharp at a smaller size than PNG.")
            }
            return Decision(format: .png, lossless: true, reason: "Screenshot or graphic: PNG keeps text and edges exact.")
        },
        Rule(name: "Photos with transparency") { $0.analysis.usesTransparency } decide: { input in
            if input.avifAvailable {
                return Decision(format: .avif, lossless: false, reason: "Photographic content with transparency: AVIF keeps alpha at the smallest size.")
            }
            if input.webpAvailable {
                return Decision(format: .webp, lossless: false, reason: "Photographic content with transparency: lossy WebP keeps alpha, which JPEG cannot.")
            }
            return Decision(format: .png, lossless: true, reason: "Transparency must be kept and only PNG can in compatibility mode.")
        },
        Rule(name: "Photos") { _ in true } decide: { input in
            if input.avifAvailable {
                return Decision(format: .avif, lossless: false, reason: "Photo: AVIF gives the smallest file. Turn on “Prefer WebP” for wider browser support.")
            }
            if input.webpAvailable {
                return Decision(format: .webp, lossless: false, reason: "Photo: WebP is 25–35% smaller than JPEG and works in every modern browser.")
            }
            return Decision(format: .jpeg, lossless: false, reason: "Photo: JPEG for maximum compatibility.")
        }
    ]

    public static func decide(_ input: Input) -> Decision {
        for rule in rules where rule.matches(input) {
            return rule.decide(input)
        }
        return Decision(format: .webp, lossless: false, reason: "Default choice.")
    }
}
