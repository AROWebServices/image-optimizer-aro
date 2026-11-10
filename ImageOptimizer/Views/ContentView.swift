import SwiftUI
import OptimizerCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    /// Anything that changes the preview.
    private struct PreviewKey: Hashable {
        var item: QueueItem.ID?
        var analysed: Bool
        var settings: OptimizationSettings
    }

    /// Column limits. The queue column takes whatever is left and never drops below `minimumDetailWidth`.
    static let sidebarRange: ClosedRange<Double> = 280...440
    static let inspectorRange: ClosedRange<Double> = 300...560
    static let minimumDetailWidth: Double = 360

    var body: some View {
        @Bindable var model = model
        // The three columns are laid out by SwiftUI alone. NavigationSplitView and .inspector are
        // backed by NSSplitView and crashed on macOS 26/27 with "needing another Update Constraints
        // in Window pass" whenever a column's minimum size changed (window restoration, first
        // import, …). A plain HStack with fixed column widths has no AppKit constraint pass at all.
        GeometryReader { proxy in
            let widths = columnWidths(available: proxy.size.width, showInspector: model.showInspector)
            HStack(spacing: 0) {
                SettingsSidebarView()
                    .frame(width: widths.sidebar)
                    .frame(maxHeight: .infinity)
                ColumnDivider(width: $model.sidebarWidth, range: Self.sidebarRange, growsRightwards: true)
                QueueContainerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.showInspector {
                    ColumnDivider(width: $model.inspectorWidth, range: Self.inspectorRange, growsRightwards: false)
                    InspectorView()
                        .frame(width: widths.inspector)
                        .frame(maxHeight: .infinity)
                        .accessibilityLabel("Inspector")
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear { model.windowDidAppear() }
        .navigationTitle("Image Optimizer ARO")
        .toolbar { toolbarContent }
        .sheet(item: $model.pendingConfirmation) { request in
            ConfirmationSheet(request: request)
        }
        .sheet(isPresented: $model.showSummary) {
            if let summary = model.lastSummary {
                BatchSummaryView(summary: summary)
            }
        }
        .sheet(isPresented: $model.showPresetManager) {
            PresetManagerView()
        }
        .alert("Save Preset", isPresented: $model.presetNamePrompt) {
            TextField("Preset name", text: $model.presetNameDraft)
            Button("Save") { model.savePresetFromPrompt() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current format, resize, quality and metadata settings will be saved.")
        }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
        .task(id: PreviewKey(item: model.selectedItem?.id, analysed: model.selectedItem?.analysis != nil, settings: model.settings)) {
            model.refreshPreview()
        }
    }

    /// Clamps the stored widths so the queue column keeps its minimum even in a narrow window.
    private func columnWidths(available: Double, showInspector: Bool) -> (sidebar: Double, inspector: Double) {
        var sidebar = min(max(model.sidebarWidth, Self.sidebarRange.lowerBound), Self.sidebarRange.upperBound)
        var inspector = showInspector ? min(max(model.inspectorWidth, Self.inspectorRange.lowerBound), Self.inspectorRange.upperBound) : 0
        let dividers: Double = showInspector ? 2 : 1
        var overflow = sidebar + inspector + dividers + Self.minimumDetailWidth - available
        if overflow > 0, showInspector {
            let give = min(overflow, inspector - Self.inspectorRange.lowerBound)
            inspector -= give
            overflow -= give
        }
        if overflow > 0 {
            let give = min(overflow, sidebar - Self.sidebarRange.lowerBound)
            sidebar -= give
        }
        return (sidebar, inspector)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                model.presentOpenPanel(foldersOnly: false)
            } label: {
                Label("Add Images", systemImage: "plus")
            }
            .help("Add images (⌘O)")
            Button {
                model.presentOpenPanel(foldersOnly: true)
            } label: {
                Label("Add Folder", systemImage: "folder.badge.plus")
            }
            .help("Add every image in a folder (⇧⌘O)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Layout", selection: Binding(get: { model.viewMode }, set: { model.viewMode = $0 })) {
                Label("List", systemImage: "list.bullet").tag(QueueViewMode.list)
                Label("Grid", systemImage: "square.grid.2x2").tag(QueueViewMode.grid)
            }
            .pickerStyle(.segmented)
            .help("Switch between list and grid")
            .accessibilityLabel("Queue layout")
            Button {
                model.showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help("Show or hide the before/after inspector (⌥⌘I)")
        }
    }
}

/// A one-point separator with a wider invisible grab area that resizes the neighbouring column.
private struct ColumnDivider: View {
    @Binding var width: Double
    let range: ClosedRange<Double>
    /// `true` when dragging to the right makes the column wider (sidebar), `false` for the inspector.
    let growsRightwards: Bool
    @State private var widthAtDragStart: Double?

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let base = widthAtDragStart ?? width
                                if widthAtDragStart == nil { widthAtDragStart = width }
                                let delta = growsRightwards ? value.translation.width : -value.translation.width
                                width = min(max(base + delta, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in widthAtDragStart = nil }
                    )
            }
            .accessibilityHidden(true)
    }
}
