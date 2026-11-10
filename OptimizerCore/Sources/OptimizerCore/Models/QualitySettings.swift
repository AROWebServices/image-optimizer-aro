import Foundation

public struct QualitySettings: Codable, Hashable, Sendable {
    public static let recommendedQuality = 82

    /// 1…100. Meaning depends on the encoder, see `OutputFormat.qualityExplanation`.
    public var quality: Int
    /// Lossless mode for formats that support it (WebP, PNG). Ignored otherwise.
    public var lossless: Bool
    public var progressiveJPEG: Bool
    /// Encoder effort 0…6 (WebP "method"). Higher is slower and smaller.
    public var effort: Int
    /// Reduce PNGs to an indexed palette when that is lossless (≤ 256 colours).
    public var optimizePNGPalette: Bool

    public init(quality: Int = QualitySettings.recommendedQuality,
                lossless: Bool = false,
                progressiveJPEG: Bool = true,
                effort: Int = 4,
                optimizePNGPalette: Bool = true) {
        self.quality = min(100, max(1, quality))
        self.lossless = lossless
        self.progressiveJPEG = progressiveJPEG
        self.effort = min(6, max(0, effort))
        self.optimizePNGPalette = optimizePNGPalette
    }

    public enum Preset: String, CaseIterable, Identifiable, Sendable {
        case maximumCompression, webOptimized, highQuality, nearLossless, lossless

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .maximumCompression: return "Maximum compression"
            case .webOptimized: return "Web optimized"
            case .highQuality: return "High quality"
            case .nearLossless: return "Near-lossless"
            case .lossless: return "Lossless"
            }
        }

        public var quality: Int {
            switch self {
            case .maximumCompression: return 60
            case .webOptimized: return QualitySettings.recommendedQuality
            case .highQuality: return 90
            case .nearLossless: return 97
            case .lossless: return 100
            }
        }

        public var isLossless: Bool { self == .lossless }

        public var effort: Int {
            switch self {
            case .maximumCompression: return 6
            default: return 4
            }
        }
    }

    public mutating func apply(_ preset: Preset) {
        quality = preset.quality
        lossless = preset.isLossless
        effort = preset.effort
    }

    public var matchingPreset: Preset? {
        Preset.allCases.first { $0.quality == quality && $0.isLossless == lossless && $0.effort == effort }
    }

    public enum ArtifactRisk: Sendable {
        case none, possible, likely

        public var message: String? {
            switch self {
            case .none: return nil
            case .possible: return "Fine detail and gradients may show slight compression artifacts at this quality."
            case .likely: return "This quality is low enough that blocking, banding and smeared detail will be visible."
            }
        }
    }

    /// Format-specific thresholds. Each encoder's quality scale differs, so the warning levels do too.
    public static func artifactRisk(quality: Int, format: OutputFormat, lossless: Bool) -> ArtifactRisk {
        if lossless && format.supportsLossless { return .none }
        let (likely, possible): (Int, Int)
        switch format {
        case .jpeg: (likely, possible) = (60, 75)
        case .webp: (likely, possible) = (50, 65)
        case .avif: (likely, possible) = (40, 55)
        case .heic: (likely, possible) = (50, 65)
        case .png, .gif: return .none
        }
        if quality < likely { return .likely }
        if quality < possible { return .possible }
        return .none
    }

    public static let crossFormatNote = "Quality percentages are encoder-specific. WebP 80, AVIF 65 and JPEG 85 look roughly alike; the same number does not mean the same thing in each format."
}
