import SwiftUI
import OptimizerCore

/// The Settings window (⌘,).
struct AppSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
            EncodersSettingsTab()
                .tabItem { Label("Encoders", systemImage: "cpu") }
            FoldersSettingsTab()
                .tabItem { Label("Folders", systemImage: "folder") }
        }
        .frame(width: 520, height: 360)
    }
}

struct GeneralSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Picker("File sizes", selection: $preferences.values.byteUnitStyle) {
                ForEach(ByteUnitStyle.allCases) { Text($0.displayName).tag($0) }
            }
            Stepper("Parallel images: \(preferences.values.maxConcurrency)", value: $preferences.values.maxConcurrency, in: 1...8)
            Text("More parallel images finish batches faster but use more memory. This Mac has \(ProcessInfo.processInfo.activeProcessorCount) cores.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Show summary after each export", isOn: $preferences.values.showSummaryAfterExport)
            Toggle("Reveal the output folder in Finder after export", isOn: $preferences.values.revealInFinderAfterExport)
            Section {
                Button("Reset Optimization Settings to Defaults") { model.resetSettings() }
            }
        }
        .formStyle(.grouped)
    }
}

struct EncodersSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ForEach(OutputFormat.allCases) { format in
                    LabeledContent(format.displayName) {
                        HStack {
                            Text(model.capabilities.encoderDescription(for: format))
                                .foregroundStyle(model.capabilities.supports(format) ? .primary : .secondary)
                            Image(systemName: model.capabilities.supports(format) ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(model.capabilities.supports(format) ? .green : .secondary)
                        }
                    }
                }
            } header: {
                Text("Available encoders")
            } footer: {
                Text("WebP is encoded by libwebp compiled into the app, because macOS can read but not write WebP. AVIF and HEIC use the system encoders in ImageIO. No external tools are required.")
            }
            Section("Decoding") {
                LabeledContent("WebP input", value: model.capabilities.canDecodeWebP ? "Supported" : "Not supported")
                LabeledContent("AVIF input", value: model.capabilities.canDecodeAVIF ? "Supported" : "Not supported")
                LabeledContent("SVG input", value: "Rasterized with AppKit")
            }
        }
        .formStyle(.grouped)
    }
}

struct FoldersSettingsTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                if model.folderAccess.grantedFolders.isEmpty {
                    Text("No folders remembered yet. The app asks for access the first time it needs to write somewhere.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.folderAccess.grantedFolders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder")
                        Text((folder.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Forget") { model.folderAccess.revoke(folder) }
                            .controlSize(.small)
                    }
                }
            } header: {
                Text("Folders with saved access")
            } footer: {
                Text("Inside the App Sandbox the app can only write to folders you have chosen. These security-scoped bookmarks let it reuse them without asking again.")
            }
        }
        .formStyle(.grouped)
    }
}
