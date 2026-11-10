import Foundation

/// A named bundle of format, resize, quality and metadata settings.
/// Output destination settings are intentionally not part of a preset.
public struct Preset: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var isBuiltIn: Bool
    public var format: FormatSelection
    public var resize: ResizeSettings
    public var quality: QualitySettings
    public var metadata: MetadataSettings
    public var auto: AutoOptimizeSettings

    public init(id: UUID = UUID(),
                name: String,
                isBuiltIn: Bool = false,
                format: FormatSelection,
                resize: ResizeSettings,
                quality: QualitySettings,
                metadata: MetadataSettings,
                auto: AutoOptimizeSettings = AutoOptimizeSettings()) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.format = format
        self.resize = resize
        self.quality = quality
        self.metadata = metadata
        self.auto = auto
    }

    public init(id: UUID = UUID(), name: String, isBuiltIn: Bool = false, settings: OptimizationSettings) {
        self.init(id: id, name: name, isBuiltIn: isBuiltIn,
                  format: settings.format, resize: settings.resize, quality: settings.quality,
                  metadata: settings.metadata, auto: settings.auto)
    }

    /// Applies the preset while keeping the current output destination.
    public func apply(to settings: inout OptimizationSettings) {
        settings.format = format
        settings.resize = resize
        settings.quality = quality
        settings.metadata = metadata
        settings.auto = auto
    }

    public func matches(_ settings: OptimizationSettings) -> Bool {
        settings.format == format && settings.resize == resize && settings.quality == quality
            && settings.metadata == metadata && settings.auto == auto
    }

    // Stable identifiers so built-in presets can be recognised across launches.
    private static func stableID(_ string: String) -> UUID { UUID(uuidString: string)! }

    public static let builtIns: [Preset] = [
        Preset(id: stableID("00000000-0000-0000-0000-000000000001"),
               name: "Website images",
               isBuiltIn: true,
               format: .auto,
               resize: ResizeSettings(mode: .fit, width: 2560, height: 2560),
               quality: QualitySettings(quality: 82),
               metadata: MetadataSettings(policy: .colorProfileOnly),
               auto: AutoOptimizeSettings(isEnabled: true)),
        Preset(id: stableID("00000000-0000-0000-0000-000000000002"),
               name: "Web photos",
               isBuiltIn: true,
               format: .webp,
               resize: ResizeSettings(mode: .fit, width: 2560, height: 2560),
               quality: QualitySettings(quality: 80),
               metadata: MetadataSettings(policy: .removeAll)),
        Preset(id: stableID("00000000-0000-0000-0000-000000000003"),
               name: "Transparent graphics",
               isBuiltIn: true,
               format: .webp,
               resize: ResizeSettings(mode: .none),
               quality: QualitySettings(quality: 100, lossless: true, effort: 5),
               metadata: MetadataSettings(policy: .removeAll)),
        Preset(id: stableID("00000000-0000-0000-0000-000000000004"),
               name: "Screenshots",
               isBuiltIn: true,
               format: .png,
               resize: ResizeSettings(mode: .fit, width: 2560, height: 2560),
               quality: QualitySettings(quality: 100, lossless: true),
               metadata: MetadataSettings(policy: .removeAll)),
        Preset(id: stableID("00000000-0000-0000-0000-000000000005"),
               name: "Maximum compression",
               isBuiltIn: true,
               format: .webp,
               resize: ResizeSettings(mode: .fit, width: 1920, height: 1920),
               quality: QualitySettings(quality: 60, effort: 6),
               metadata: MetadataSettings(policy: .removeAll)),
        Preset(id: stableID("00000000-0000-0000-0000-000000000006"),
               name: "Lossless assets",
               isBuiltIn: true,
               format: .original,
               resize: ResizeSettings(mode: .none),
               quality: QualitySettings(quality: 100, lossless: true, effort: 6),
               metadata: MetadataSettings(policy: .copyrightOnly, convertToSRGB: false))
    ]
}
