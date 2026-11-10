import Foundation
import Observation
import OptimizerCore

/// App-wide preferences shown in the Settings window.
struct AppPreferencesValues: Codable, Equatable {
    var byteUnitStyle: ByteUnitStyle = .decimal
    var maxConcurrency: Int = BatchProcessor.defaultConcurrency
    var showSummaryAfterExport: Bool = true
    var revealInFinderAfterExport: Bool = false
    var thumbnailPixelSize: Int = 160

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppPreferencesValues()
        byteUnitStyle = try container.decodeIfPresent(ByteUnitStyle.self, forKey: .byteUnitStyle) ?? defaults.byteUnitStyle
        maxConcurrency = try container.decodeIfPresent(Int.self, forKey: .maxConcurrency) ?? defaults.maxConcurrency
        showSummaryAfterExport = try container.decodeIfPresent(Bool.self, forKey: .showSummaryAfterExport) ?? defaults.showSummaryAfterExport
        revealInFinderAfterExport = try container.decodeIfPresent(Bool.self, forKey: .revealInFinderAfterExport) ?? defaults.revealInFinderAfterExport
        thumbnailPixelSize = try container.decodeIfPresent(Int.self, forKey: .thumbnailPixelSize) ?? defaults.thumbnailPixelSize
    }
}

@Observable @MainActor
final class AppPreferences {
    var values: AppPreferencesValues {
        didSet { Persistence.save(values, key: Persistence.preferencesKey) }
    }

    init() {
        values = Persistence.load(AppPreferencesValues.self, key: Persistence.preferencesKey) ?? AppPreferencesValues()
    }

    func format(_ bytes: Int64) -> String {
        ByteFormatting.string(bytes, style: values.byteUnitStyle)
    }
}
