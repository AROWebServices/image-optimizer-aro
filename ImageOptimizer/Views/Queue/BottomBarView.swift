import SwiftUI
import OptimizerCore

/// Persistent toolbar under the queue: add, auto optimize, progress, cancel, export.
struct BottomBarView: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingClear = false

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 12) {
            Button {
                model.presentOpenPanel(foldersOnly: false)
            } label: {
                Label("Add Images", systemImage: "plus")
            }
            .disabled(model.isProcessing)

            if !model.items.isEmpty {
                Button {
                    isConfirmingClear = true
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(model.isProcessing)
                .help("Remove every image from the queue (⇧⌘⌫). Files on disk are not touched.")
                .confirmationDialog("Clear the queue?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
                    Button("Clear \(model.items.count) Images", role: .destructive) { model.clearQueue() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("All \(model.items.count) images are removed from the queue. Nothing on disk is deleted; files you already exported stay where they are.")
                }
            }

            Toggle(isOn: $model.settings.auto.isEnabled) {
                Label("Auto Optimize", systemImage: "wand.and.stars")
            }
            .toggleStyle(.button)
            .help("Pick format, size and quality automatically for every image (⇧⌘A)")

            Spacer(minLength: 8)

            // The status text may truncate so the bar never forces the window wider.
            statusArea
                .layoutPriority(-1)
                .frame(maxWidth: 420)

            Spacer(minLength: 8)

            if model.isProcessing {
                Button(model.isPaused ? "Resume" : "Pause") { model.togglePause() }
                    .help(model.isPaused ? "Continue processing (⇧⌘P)" : "Finish current files, then wait (⇧⌘P)")
                Button("Cancel", role: .cancel) { model.cancel() }
                    .keyboardShortcut(.cancelAction)
            }

            Button {
                model.export()
            } label: {
                Label(exportTitle, systemImage: "square.and.arrow.up")
                    .frame(minWidth: 90)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canExport || model.settingsProblem != nil)
            .help(model.settingsProblem ?? "Optimize and export the queue (⌘E)")
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var exportTitle: String {
        let count = model.readyItems.count
        return count > 1 ? "Export \(count)" : "Export"
    }

    @ViewBuilder
    private var statusArea: some View {
        if model.isProcessing {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(model.progressCompleted), total: Double(max(1, model.progressTotal)))
                    .frame(minWidth: 120, maxWidth: 260)
                Text(model.isPaused ? "Paused · \(model.progressCompleted) of \(model.progressTotal)" : "Optimizing \(model.progressCompleted + 1 > model.progressTotal ? model.progressTotal : model.progressCompleted + 1) of \(model.progressTotal)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
        } else if let summary = model.lastSummary {
            Button {
                model.showSummary = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: summary.failed > 0 ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(summary.failed > 0 ? .orange : .green)
                    Text(summaryLine(summary))
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .buttonStyle(.plain)
            .help("Show the batch summary")
        } else if model.isImporting {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading images…").font(.callout).foregroundStyle(.secondary)
            }
        } else if !model.items.isEmpty {
            Text("\(model.items.count) images · \(model.format(model.totalOriginalBytes))")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func summaryLine(_ summary: BatchSummary) -> String {
        var text = "\(summary.succeeded + summary.keptOriginal) of \(summary.processed) done · saved \(model.format(summary.totalSaved)) (\(ByteFormatting.percent(summary.averageReductionPercent)))"
        if summary.failed > 0 { text += " · \(summary.failed) failed" }
        if summary.skipped > 0 { text += " · \(summary.skipped) skipped" }
        if summary.wasCancelled { text += " · cancelled" }
        return text
    }
}
