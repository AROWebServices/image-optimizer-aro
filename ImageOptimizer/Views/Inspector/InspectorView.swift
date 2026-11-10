import SwiftUI
import OptimizerCore

/// Right column: before/after comparison and details for the selected image.
struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let item = model.selectedItem {
            ItemInspectorView(item: item)
        } else if model.selection.count > 1 {
            SelectionSummaryView(items: model.selectedItems)
        } else {
            ContentUnavailableView("No Selection", systemImage: "photo.badge.magnifyingglass",
                                   description: Text("Select an image to compare the original with the optimized result."))
        }
    }
}

struct SelectionSummaryView: View {
    @Environment(AppModel.self) private var model
    let items: [QueueItem]

    var body: some View {
        let total = items.reduce(Int64(0)) { $0 + ($1.analysis?.fileSize ?? 0) }
        let done = items.compactMap(\.result).filter { $0.status.isSuccess }
        let optimized = done.reduce(Int64(0)) { $0 + $1.optimizedSize }
        let original = done.reduce(Int64(0)) { $0 + $1.originalSize }
        Form {
            Section("\(items.count) images selected") {
                LabeledContent("Total size", value: model.format(total))
                if !done.isEmpty {
                    LabeledContent("Optimized", value: "\(done.count) files · \(model.format(optimized))")
                    LabeledContent("Saved", value: "\(model.format(original - optimized)) (\(ByteFormatting.percent(original > 0 ? (1 - Double(optimized) / Double(original)) * 100 : 0)))")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ItemInspectorView: View {
    @Environment(AppModel.self) private var model
    let item: QueueItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if item.analysis != nil {
                    ComparisonView(item: item)
                    detailsGrid
                    decisions
                } else if case .unreadable(let message) = item.status {
                    InlineNote(text: message, systemImage: "exclamationmark.triangle.fill", tint: .red)
                }
            }
            .padding(16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.middle)
            Text((item.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                StatusBadge(status: item.status)
                Spacer()
                Button("Reveal in Finder") { model.revealInFinder(item.result?.outputURL ?? item.url) }
                    .controlSize(.small)
            }
        }
    }

    private var plan: ItemPlan? { model.preview.plan }

    private var detailsGrid: some View {
        let analysis = item.analysis
        let result = item.result?.status.isSuccess == true ? item.result : nil
        let outputFormat = result?.outputFormat ?? plan?.outputFormat
        let outputSize = result?.outputPixelSize ?? model.preview.outputSize ?? plan?.outputSize
        let outputBytes = result?.optimizedSize ?? model.preview.estimatedSize
        return GroupBox("Details") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("").frame(width: 80)
                    Text("Original").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(result == nil ? "Output (estimate)" : "Output").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Format").foregroundStyle(.secondary)
                    Text(analysis?.format.displayName ?? "–")
                    Text(outputFormat?.displayName ?? "–")
                }
                GridRow {
                    Text("Dimensions").foregroundStyle(.secondary)
                    Text(analysis?.pixelSize.description ?? "–")
                    Text(outputSize?.description ?? "–")
                }
                GridRow {
                    Text("File size").foregroundStyle(.secondary)
                    Text(analysis.map { model.format($0.fileSize) } ?? "–")
                    HStack(spacing: 6) {
                        Text(outputBytes.map { model.format($0) } ?? (model.preview.isRendering ? "…" : "–"))
                        if let outputBytes, let analysis, analysis.fileSize > 0 {
                            ReductionText(percent: (1 - Double(outputBytes) / Double(analysis.fileSize)) * 100)
                        }
                    }
                }
                GridRow {
                    Text("Content").foregroundStyle(.secondary)
                    Text(contentDescription)
                    Text(plan.map { $0.lossless ? "Lossless" : ($0.outputFormat.usesQualitySlider ? "Quality \($0.quality)" : "Lossless") } ?? "–")
                }
                if let analysis, analysis.hasEXIF || analysis.hasGPS || !analysis.isSRGB {
                    GridRow {
                        Text("Metadata").foregroundStyle(.secondary)
                        Text([analysis.hasEXIF ? "EXIF" : nil, analysis.hasGPS ? "GPS" : nil, analysis.colorSpaceName].compactMap { $0 }.joined(separator: ", "))
                            .lineLimit(2)
                        Text(model.settings.metadata.policy.displayName).lineLimit(2)
                    }
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var contentDescription: String {
        guard let analysis = item.analysis else { return "–" }
        var parts = [analysis.contentKind.displayName]
        if analysis.usesTransparency { parts.append("transparent") }
        if analysis.isAnimated { parts.append("\(analysis.frameCount) frames") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var decisions: some View {
        let decisionList = item.result?.decisions ?? (plan?.decisions ?? []) + model.preview.notes
        let warnings = item.result?.warnings ?? plan?.warnings ?? []
        if !warnings.isEmpty {
            GroupBox("Before you export") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(warnings, id: \.self) { warning in
                        WarningLabel(warning: warning)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if !decisionList.isEmpty {
            GroupBox(item.result == nil ? "What will happen" : "What happened") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(decisionList.enumerated()), id: \.offset) { _, decision in
                        Label {
                            Text(decision).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "checkmark").foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if let message = model.preview.errorMessage {
            InlineNote(text: message, systemImage: "exclamationmark.triangle.fill", tint: .red)
        }
    }
}
