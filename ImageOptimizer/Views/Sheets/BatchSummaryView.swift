import SwiftUI
import OptimizerCore

struct BatchSummaryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let summary: BatchSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: summary.failed > 0 ? "exclamationmark.circle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(summary.failed > 0 ? .orange : .green)
                VStack(alignment: .leading) {
                    Text(summary.wasCancelled ? "Export cancelled" : "Export finished")
                        .font(.title2.weight(.semibold))
                    Text("\(summary.processed) files in \(duration)")
                        .foregroundStyle(.secondary)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    stat("Processed", "\(summary.processed)")
                    stat("Optimized", "\(summary.succeeded)")
                    stat("Kept original", "\(summary.keptOriginal)")
                }
                GridRow {
                    stat("Skipped", "\(summary.skipped)", tint: summary.skipped > 0 ? .orange : nil)
                    stat("Failed", "\(summary.failed)", tint: summary.failed > 0 ? .red : nil)
                    stat("Average reduction", ByteFormatting.percent(summary.averageReductionPercent), tint: .green)
                }
                GridRow {
                    stat("Original total", model.format(summary.totalOriginalSize))
                    stat("Optimized total", model.format(summary.totalOptimizedSize))
                    stat("Space saved", model.format(summary.totalSaved), tint: .green)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            if summary.failed > 0 || summary.skipped > 0 {
                Text("Failed and skipped files show the reason in the queue. Hover over a red message to read it in full.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if !model.lastOutputFolders.isEmpty {
                    Button("Show in Finder") { model.revealLastExport() }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private var duration: String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = summary.duration >= 60 ? [.minute, .second] : [.second]
        formatter.unitsStyle = .short
        return formatter.string(from: max(1, summary.duration)) ?? "\(Int(summary.duration)) s"
    }

    private func stat(_ title: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.medium).monospacedDigit()).foregroundStyle(tint ?? .primary)
        }
        .frame(minWidth: 130, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
