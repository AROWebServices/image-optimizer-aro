import Foundation

/// Settings for the one-click "Auto optimize" mode.
public struct AutoOptimizeSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    /// Images wider or taller than this are scaled down (fit, never enlarged).
    public var maxWidth: Int
    public var maxHeight: Int
    /// Advanced: allow the selector to choose any format, including AVIF, when it is the best fit.
    public var useBestFormatAutomatically: Bool
    /// When the best format would be AVIF, pick WebP instead for broader browser support.
    public var preferWebPOverAVIF: Bool
    /// Only produce JPEG, PNG and GIF, for sites that must support very old browsers.
    public var compatibilityMode: Bool
    public var quality: Int

    public init(isEnabled: Bool = false,
                maxWidth: Int = 2560,
                maxHeight: Int = 2560,
                useBestFormatAutomatically: Bool = true,
                preferWebPOverAVIF: Bool = true,
                compatibilityMode: Bool = false,
                quality: Int = QualitySettings.recommendedQuality) {
        self.isEnabled = isEnabled
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.useBestFormatAutomatically = useBestFormatAutomatically
        self.preferWebPOverAVIF = preferWebPOverAVIF
        self.compatibilityMode = compatibilityMode
        self.quality = min(100, max(1, quality))
    }

    /// AVIF is only chosen automatically when both switches allow it.
    public var allowsAVIF: Bool { useBestFormatAutomatically && !preferWebPOverAVIF && !compatibilityMode }
}
