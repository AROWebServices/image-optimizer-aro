import Foundation

/// Everything that influences how a batch is processed. Persisted by the app as JSON.
public struct OptimizationSettings: Codable, Hashable, Sendable {
    public var format: FormatSelection
    public var resize: ResizeSettings
    public var quality: QualitySettings
    public var metadata: MetadataSettings
    public var output: OutputSettings
    public var auto: AutoOptimizeSettings

    public init(format: FormatSelection = .webp,
                resize: ResizeSettings = ResizeSettings(),
                quality: QualitySettings = QualitySettings(),
                metadata: MetadataSettings = MetadataSettings(),
                output: OutputSettings = OutputSettings(),
                auto: AutoOptimizeSettings = AutoOptimizeSettings()) {
        self.format = format
        self.resize = resize
        self.quality = quality
        self.metadata = metadata
        self.output = output
        self.auto = auto
    }

    public static let `default` = OptimizationSettings()

    /// Settings the pipeline actually uses. When Auto optimize is on, its rules override
    /// the manual format, resize and quality sections.
    public var resolvedForProcessing: OptimizationSettings {
        guard auto.isEnabled else { return self }
        var resolved = self
        resolved.format = .auto
        resolved.resize = ResizeSettings(mode: .fit,
                                         width: auto.maxWidth,
                                         height: auto.maxHeight,
                                         lockAspectRatio: true,
                                         onlyShrink: true,
                                         sharpenAfterResize: false)
        resolved.quality = QualitySettings(quality: auto.quality, lossless: false, progressiveJPEG: true, effort: 4, optimizePNGPalette: true)
        if resolved.metadata.policy == .keepAll {
            resolved.metadata.policy = .colorProfileOnly
        }
        return resolved
    }

    /// Decodes settings saved by an older version, falling back to defaults field by field.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = OptimizationSettings.default
        format = try container.decodeIfPresent(FormatSelection.self, forKey: .format) ?? defaults.format
        resize = try container.decodeIfPresent(ResizeSettings.self, forKey: .resize) ?? defaults.resize
        quality = try container.decodeIfPresent(QualitySettings.self, forKey: .quality) ?? defaults.quality
        metadata = try container.decodeIfPresent(MetadataSettings.self, forKey: .metadata) ?? defaults.metadata
        output = try container.decodeIfPresent(OutputSettings.self, forKey: .output) ?? defaults.output
        auto = try container.decodeIfPresent(AutoOptimizeSettings.self, forKey: .auto) ?? defaults.auto
    }
}
