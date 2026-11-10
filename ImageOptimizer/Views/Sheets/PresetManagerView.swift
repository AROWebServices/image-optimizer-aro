import SwiftUI
import OptimizerCore

/// Create, rename, duplicate, update and delete presets.
struct PresetManagerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Preset.ID?
    @State private var renameDraft = ""
    @State private var isRenaming = false

    private var selectedPreset: Preset? { model.presets.all.first { $0.id == selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Presets").font(.title3.weight(.semibold))
            HStack(alignment: .top, spacing: 12) {
                List(selection: $selected) {
                    Section("Built-in") {
                        ForEach(model.presets.builtIns) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    Section("Custom") {
                        if model.presets.customPresets.isEmpty {
                            Text("No custom presets yet").foregroundStyle(.secondary)
                        }
                        ForEach(model.presets.customPresets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                }
                .frame(width: 220, height: 300)
                .accessibilityLabel("Preset list")

                VStack(alignment: .leading, spacing: 10) {
                    if let preset = selectedPreset {
                        Text(preset.name).font(.headline)
                        PresetDescription(preset: preset)
                        Spacer()
                        HStack {
                            Button("Apply") { model.apply(preset); dismiss() }
                                .keyboardShortcut(.defaultAction)
                            Button("Duplicate") { if let copy = model.presets.duplicate(preset.id) { selected = copy.id } }
                            if !preset.isBuiltIn {
                                Button("Rename…") { renameDraft = preset.name; isRenaming = true }
                                Button("Update with Current Settings") { model.presets.update(preset.id, with: model.settings) }
                                Button("Delete", role: .destructive) { model.presets.delete(preset.id); selected = nil }
                            }
                        }
                        .controlSize(.small)
                    } else {
                        Text("Select a preset to see what it does.").foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("New from Current Settings") {
                    let preset = model.presets.add(name: "My preset", settings: model.settings)
                    selected = preset.id
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 640)
        .alert("Rename Preset", isPresented: $isRenaming) {
            TextField("Name", text: $renameDraft)
            Button("Rename") { if let id = selected { model.presets.rename(id, to: renameDraft) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct PresetDescription: View {
    let preset: Preset

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            row("Mode", preset.auto.isEnabled ? "Auto optimize (max \(preset.auto.maxWidth)×\(preset.auto.maxHeight), quality \(preset.auto.quality))" : "Manual")
            row("Format", preset.format.displayName)
            row("Resize", resizeText)
            row("Quality", preset.quality.lossless ? "Lossless" : "\(preset.quality.quality)" + (preset.quality.progressiveJPEG ? ", progressive JPEG" : ""))
            row("Metadata", preset.metadata.policy.displayName + (preset.metadata.convertToSRGB ? ", sRGB" : ", keep profile"))
        }
        .font(.callout)
    }

    private var resizeText: String {
        let resize = preset.resize
        switch resize.mode {
        case .none: return "Original size"
        case .percentage: return "\(Int(resize.percentage))%"
        default:
            let w = resize.width.map(String.init) ?? "auto"
            let h = resize.height.map(String.init) ?? "auto"
            return "\(resize.mode.displayName) \(w)×\(h)" + (resize.onlyShrink ? ", never enlarge" : "")
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value)
        }
    }
}
