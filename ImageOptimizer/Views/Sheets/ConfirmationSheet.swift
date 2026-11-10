import SwiftUI
import OptimizerCore

/// Lists everything that needs an explicit OK before the batch starts.
struct ConfirmationSheet: View {
    @Environment(AppModel.self) private var model
    let request: ConfirmationRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Please confirm before exporting", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Some of the \(request.total) images will be changed in ways that cannot be undone from the output. Files you do not confirm are skipped, never altered.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 12) {
                ForEach(request.warnings, id: \.warning) { entry in
                    HStack(alignment: .top) {
                        WarningLabel(warning: entry.warning)
                        Spacer()
                        Text(entry.count == 1 ? "1 file" : "\(entry.count) files")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if request.overwriteWarning {
                    HStack(alignment: .top) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Existing files will be overwritten").font(.callout.weight(.medium))
                                Text("Files already in the destination with the same name are replaced. Source files are never touched.").font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                        Spacer()
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button("Cancel") { model.cancelPendingExport() }
                    .keyboardShortcut(.cancelAction)
                Button("Continue and Export") { model.confirmPendingExport() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
