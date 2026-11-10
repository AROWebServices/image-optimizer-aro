import SwiftUI
import UniformTypeIdentifiers
import OptimizerCore

/// Hosts the list or grid, the drop target and the bottom toolbar.
struct QueueContainerView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false

    var body: some View {
        Group {
            if model.items.isEmpty {
                EmptyQueueView()
            } else {
                switch model.viewMode {
                case .list: QueueListView()
                case .grid: QueueGridView()
                }
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10]))
                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.importURLs(urls)
            return true
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomBarView()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let notice = model.duplicateNotice {
                HStack {
                    Label(notice, systemImage: "doc.on.doc")
                        .font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(.bar)
                .overlay(alignment: .bottom) { Divider() }
            }
        }
    }
}

struct EmptyQueueView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Drop images or folders here", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("JPEG, PNG, HEIC, TIFF, GIF, WebP, AVIF, BMP and SVG are supported. Folders are searched recursively.")
        } actions: {
            HStack {
                Button("Add Images…") { model.presentOpenPanel(foldersOnly: false) }
                    .keyboardShortcut(.defaultAction)
                Button("Add Folder…") { model.presentOpenPanel(foldersOnly: true) }
            }
        }
    }
}

struct QueueListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            ForEach(model.items) { item in
                QueueRowView(item: item)
                    .tag(item.id)
                    .contextMenu { QueueItemMenu(item: item) }
            }
            .onMove { source, destination in
                model.move(from: source, to: destination)
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds()
        .accessibilityLabel("Image queue")
    }
}

struct QueueRowView: View {
    @Environment(AppModel.self) private var model
    let item: QueueItem

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(image: item.thumbnail, isAnimated: item.analysis?.isAnimated ?? false, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if let analysis = item.analysis {
                        FormatBadge(text: analysis.format.displayName, tint: analysis.format.tint)
                        Text(analysis.pixelSize.description)
                        Text("·")
                        Text(model.format(analysis.fileSize))
                        if analysis.usesTransparency {
                            Image(systemName: "square.on.square.dashed").help("Uses transparency")
                        }
                        if analysis.isAnimated {
                            Image(systemName: "film").help("\(analysis.frameCount) frames")
                        }
                        if analysis.isOriented {
                            Image(systemName: "rotate.right").help("EXIF orientation \(analysis.orientation) will be applied")
                        }
                    } else if case .unreadable(let message) = item.status {
                        Text(message).foregroundStyle(.red).lineLimit(1)
                    } else {
                        Text("Reading…")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            resultColumn
            StatusBadge(status: item.status)
                .frame(width: 130, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var resultColumn: some View {
        if let result = item.result, result.status.isSuccess {
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    FormatBadge(text: result.outputFormat.displayName, tint: result.outputFormat.tint)
                    Text(result.outputPixelSize.description).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(model.format(result.optimizedSize)).font(.caption).foregroundStyle(.secondary)
                    ReductionText(percent: result.reductionPercent)
                }
            }
            .frame(minWidth: 150, alignment: .trailing)
        } else if let result = item.result, case .failed(let message) = result.status {
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
                .frame(maxWidth: 260, alignment: .trailing)
                .help(message)
        } else if let plan = planPreview {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                FormatBadge(text: plan.outputFormat.displayName, tint: plan.outputFormat.tint)
                Text(plan.outputSize.description).font(.caption).foregroundStyle(.secondary)
                if !plan.warnings.isEmpty {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(plan.warnings.map(\.title).joined(separator: "\n"))
                }
            }
            .frame(minWidth: 150, alignment: .trailing)
        }
    }

    private var planPreview: ItemPlan? {
        guard let job = item.job else { return nil }
        let context = PipelineContext(settings: model.settings, capabilities: model.capabilities)
        return OptimizationPipeline.plan(for: job, context: context)
    }

    private var accessibilitySummary: String {
        var parts = [item.name]
        if let analysis = item.analysis {
            parts.append("\(analysis.format.displayName), \(analysis.pixelSize.width) by \(analysis.pixelSize.height) pixels, \(model.format(analysis.fileSize))")
        }
        if let result = item.result, result.status.isSuccess {
            parts.append("optimized to \(result.outputFormat.displayName), \(model.format(result.optimizedSize)), \(ByteFormatting.percent(result.reductionPercent))")
        }
        parts.append(item.status.label)
        return parts.joined(separator: ". ")
    }
}

struct QueueItemMenu: View {
    @Environment(AppModel.self) private var model
    let item: QueueItem

    var body: some View {
        Button("Reveal Original in Finder") { model.revealInFinder(item.url) }
        if let output = item.result?.outputURL {
            Button("Reveal Optimized File in Finder") { model.revealInFinder(output) }
        }
        Divider()
        Button("Remove from Queue", role: .destructive) { model.remove([item.id]) }
            .disabled(model.isProcessing)
        Button("Clear Queue", role: .destructive) { model.clearQueue() }
            .disabled(model.isProcessing)
    }
}

struct QueueGridView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(model.items) { item in
                    QueueGridCell(item: item, isSelected: model.selection.contains(item.id))
                        .onTapGesture {
                            if NSEvent.modifierFlags.contains(.command) {
                                if model.selection.contains(item.id) { model.selection.remove(item.id) } else { model.selection.insert(item.id) }
                            } else {
                                model.selection = [item.id]
                            }
                        }
                        .contextMenu { QueueItemMenu(item: item) }
                }
            }
            .padding(16)
        }
        .accessibilityLabel("Image queue grid")
    }
}

struct QueueGridCell: View {
    @Environment(AppModel.self) private var model
    let item: QueueItem
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ThumbnailView(image: item.thumbnail, isAnimated: item.analysis?.isAnimated ?? false, size: 150)
                .frame(maxWidth: .infinity)
            Text(item.name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
            if let analysis = item.analysis {
                Text("\(analysis.format.displayName) · \(analysis.pixelSize.description) · \(model.format(analysis.fileSize))")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if let result = item.result, result.status.isSuccess {
                HStack(spacing: 4) {
                    FormatBadge(text: result.outputFormat.displayName, tint: result.outputFormat.tint)
                    Text(model.format(result.optimizedSize)).font(.caption2).foregroundStyle(.secondary)
                    ReductionText(percent: result.reductionPercent)
                }
            } else {
                StatusBadge(status: item.status)
            }
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
