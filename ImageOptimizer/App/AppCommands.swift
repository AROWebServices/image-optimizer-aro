import SwiftUI
import OptimizerCore

/// Native menu bar commands. Every toolbar action is reachable from here with a keyboard shortcut.
struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Images…") { model.presentOpenPanel(foldersOnly: false) }
                .keyboardShortcut("o", modifiers: .command)
            Button("Add Folder…") { model.presentOpenPanel(foldersOnly: true) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Export Optimized Images") { model.export() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!model.canExport)
            Button("Reveal Last Export in Finder") { model.revealLastExport() }
                .disabled(model.lastSummary == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Remove Selected Images") { model.removeSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.selection.isEmpty || model.isProcessing)
            Button("Clear Queue") { model.clearQueue() }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(model.items.isEmpty || model.isProcessing)
            Button("Select All Images") { model.selectAll() }
                .disabled(model.items.isEmpty)
        }

        CommandMenu("Process") {
            Toggle("Auto Optimize", isOn: Binding(get: { model.settings.auto.isEnabled },
                                                   set: { model.settings.auto.isEnabled = $0 }))
                .keyboardShortcut("a", modifiers: [.command, .shift])
            Divider()
            Button(model.isPaused ? "Resume Export" : "Pause Export") { model.togglePause() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!model.isProcessing)
            Button("Cancel Export") { model.cancel() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!model.isProcessing)
            Divider()
            Button("Manage Presets…") { model.showPresetManager = true }
            Button("Save Current Settings as Preset…") { model.promptForPresetName() }
            Divider()
            Button("Reset Settings to Defaults") { model.resetSettings() }
                .disabled(model.isProcessing)
        }

        CommandGroup(after: .sidebar) {
            Button(model.showInspector ? "Hide Inspector" : "Show Inspector") { model.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Picker("Queue Layout", selection: Binding(get: { model.viewMode }, set: { model.viewMode = $0 })) {
                Text("List").tag(QueueViewMode.list)
                Text("Grid").tag(QueueViewMode.grid)
            }
            .keyboardShortcut("l", modifiers: [.command, .option])
            Divider()
        }
    }
}
