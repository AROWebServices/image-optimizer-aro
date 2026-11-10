import Foundation
import Observation
import OptimizerCore

/// Built-in presets plus the user's own, persisted as JSON.
@Observable @MainActor
final class PresetStore {
    private(set) var customPresets: [Preset] {
        didSet { Persistence.save(customPresets, key: Persistence.presetsKey) }
    }

    init() {
        customPresets = Persistence.load([Preset].self, key: Persistence.presetsKey) ?? []
    }

    var builtIns: [Preset] { Preset.builtIns }
    var all: [Preset] { builtIns + customPresets }

    func preset(matching settings: OptimizationSettings) -> Preset? {
        all.first { $0.matches(settings) }
    }

    @discardableResult
    func add(name: String, settings: OptimizationSettings) -> Preset {
        let preset = Preset(name: uniqueName(name), settings: settings)
        customPresets.append(preset)
        return preset
    }

    func rename(_ id: Preset.ID, to name: String) {
        guard let index = customPresets.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        customPresets[index].name = trimmed
    }

    @discardableResult
    func duplicate(_ id: Preset.ID) -> Preset? {
        guard let source = all.first(where: { $0.id == id }) else { return nil }
        var copy = source
        copy.id = UUID()
        copy.isBuiltIn = false
        copy.name = uniqueName(source.name + " copy")
        customPresets.append(copy)
        return copy
    }

    func update(_ id: Preset.ID, with settings: OptimizationSettings) {
        guard let index = customPresets.firstIndex(where: { $0.id == id }) else { return }
        let name = customPresets[index].name
        customPresets[index] = Preset(id: id, name: name, settings: settings)
    }

    func delete(_ id: Preset.ID) {
        customPresets.removeAll { $0.id == id }
    }

    func uniqueName(_ base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? "Custom preset" : trimmed
        let names = Set(all.map(\.name))
        if !names.contains(candidate) { return candidate }
        var counter = 2
        while names.contains("\(candidate) \(counter)") { counter += 1 }
        return "\(candidate) \(counter)"
    }
}
