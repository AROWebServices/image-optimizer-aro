import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import OptimizerCore

struct AlertMessage: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// What the user must acknowledge before an export starts.
struct ConfirmationRequest: Identifiable {
    let id = UUID()
    var warnings: [(warning: ItemWarning, count: Int)]
    var overwriteWarning: Bool
    var total: Int
}

/// Central state for the main window. All mutation happens on the main actor; heavy work runs
/// in detached tasks and reports back through async streams.
@Observable @MainActor
final class AppModel {
    // MARK: Queue
    private(set) var items: [QueueItem] = []
    var selection: Set<QueueItem.ID> = []
    var viewMode: QueueViewMode {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: Persistence.viewModeKey) }
    }
    var showInspector: Bool {
        didSet { UserDefaults.standard.set(showInspector, forKey: Persistence.inspectorKey) }
    }
    /// Column widths of the main window. Stored as plain numbers; the layout clamps them.
    var sidebarWidth: Double {
        didSet { UserDefaults.standard.set(sidebarWidth, forKey: Persistence.sidebarWidthKey) }
    }
    var inspectorWidth: Double {
        didSet { UserDefaults.standard.set(inspectorWidth, forKey: Persistence.inspectorWidthKey) }
    }
    private(set) var isImporting = false
    private(set) var duplicateNotice: String?
    /// Files handed over by Finder before the window exists are imported once it has appeared.
    private var isWindowReady = false
    private var pendingOpenURLs: [URL] = []

    // MARK: Settings
    var settings: OptimizationSettings {
        didSet { Persistence.save(settings, key: Persistence.settingsKey) }
    }
    let presets = PresetStore()
    let preferences = AppPreferences()
    let folderAccess = FolderAccessStore()
    let capabilities = EncoderCapabilities.current
    let preview = PreviewModel()

    // MARK: Processing
    private(set) var isProcessing = false
    private(set) var isPaused = false
    private(set) var progressCompleted = 0
    private(set) var progressTotal = 0
    private(set) var lastSummary: BatchSummary?
    private(set) var lastOutputFolders: [URL] = []
    private var processor: BatchProcessor?
    private var pendingExport: PendingExport?

    // MARK: Presentation
    var pendingConfirmation: ConfirmationRequest?
    var showSummary = false
    var showPresetManager = false
    var presetNamePrompt = false
    var presetNameDraft = ""
    var alert: AlertMessage?

    struct PendingExport {
        var items: [BatchItem]
        var context: PipelineContext
        var report: PreflightReport
    }

    init() {
        settings = Persistence.load(OptimizationSettings.self, key: Persistence.settingsKey) ?? .default
        viewMode = QueueViewMode(rawValue: UserDefaults.standard.string(forKey: Persistence.viewModeKey) ?? "") ?? .list
        showInspector = UserDefaults.standard.object(forKey: Persistence.inspectorKey) as? Bool ?? true
        sidebarWidth = UserDefaults.standard.object(forKey: Persistence.sidebarWidthKey) as? Double ?? 330
        inspectorWidth = UserDefaults.standard.object(forKey: Persistence.inspectorWidthKey) as? Double ?? 360
    }

    // MARK: - Derived state

    var selectedItems: [QueueItem] { items.filter { selection.contains($0.id) } }
    var selectedItem: QueueItem? { selection.count == 1 ? selectedItems.first : nil }
    var readyItems: [QueueItem] { items.filter(\.canProcess) }
    var canExport: Bool { !isProcessing && !readyItems.isEmpty }

    var totalOriginalBytes: Int64 { items.reduce(0) { $0 + ($1.analysis?.fileSize ?? 0) } }

    /// Settings-level problem that blocks export, if any.
    var settingsProblem: String? {
        let resolved = settings.resolvedForProcessing
        if let message = resolved.resize.validationMessage { return message }
        if resolved.output.destination == .customFolder && resolved.output.customFolderBookmark == nil { return "Choose an output folder in the Output section." }
        if let fixed = resolved.format.fixedFormat, !capabilities.supports(fixed) { return "\(fixed.displayName) cannot be encoded on this Mac. Choose another format." }
        return nil
    }

    func format(_ bytes: Int64) -> String { preferences.format(bytes) }

    // MARK: - Importing

    /// Entry point for files opened from Finder or the Dock.
    func openExternal(_ urls: [URL]) {
        if isWindowReady {
            importURLs(urls)
        } else {
            pendingOpenURLs.append(contentsOf: urls)
        }
    }

    func windowDidAppear() {
        isWindowReady = true
        guard !pendingOpenURLs.isEmpty else { return }
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        // Let the first layout pass settle before the queue changes shape.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            importURLs(urls)
        }
    }

    func presentOpenPanel(foldersOnly: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = !foldersOnly
        panel.canCreateDirectories = false
        panel.allowedContentTypes = foldersOnly ? [.folder] : ImageFormat.importableTypes + [.folder]
        panel.title = foldersOnly ? "Add Folder" : "Add Images"
        panel.message = foldersOnly ? "Every supported image inside the folder (and its subfolders) will be added." : "Choose images or folders to optimize."
        panel.prompt = "Add"
        panel.begin { [weak self] response in
            guard response == .OK, let self else { return }
            self.importURLs(panel.urls)
        }
    }

    /// Entry point for the open panel and drag-and-drop. Folders are expanded recursively.
    func importURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        duplicateNotice = nil
        Task {
            let discovered = await Task.detached(priority: .userInitiated) { AppModel.expand(urls) }.value
            var added: [QueueItem] = []
            var duplicates = 0
            var existing = Set(items.map { $0.url.standardizedFileURL.path })
            for entry in discovered {
                let key = entry.url.standardizedFileURL.path
                if existing.contains(key) {
                    duplicates += 1
                    continue
                }
                existing.insert(key)
                let item = QueueItem(url: entry.url, importRoot: entry.root)
                added.append(item)
            }
            for root in Set(discovered.compactMap(\.root)) {
                folderAccess.grant(root, persist: false)
            }
            items.append(contentsOf: added)
            if duplicates > 0 {
                duplicateNotice = duplicates == 1 ? "1 duplicate was skipped." : "\(duplicates) duplicates were skipped."
            }
            if added.isEmpty && duplicates == 0 && !discovered.isEmpty {
                duplicateNotice = nil
            }
            if discovered.isEmpty {
                alert = AlertMessage(title: "No images found", message: "None of the dropped items are supported images. Supported: JPEG, PNG, HEIC, TIFF, GIF, WebP, AVIF, BMP and SVG.")
            }
            await analyze(added)
            isImporting = false
        }
    }

    struct DiscoveredFile: Sendable {
        var url: URL
        var root: URL?
    }

    nonisolated static func expand(_ urls: [URL]) -> [DiscoveredFile] {
        var result: [DiscoveredFile] = []
        let fileManager = FileManager.default
        for url in urls {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let keys: [URLResourceKey] = [.isRegularFileKey, .isHiddenKey]
                guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                var files: [URL] = []
                for case let child as URL in enumerator {
                    guard let values = try? child.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                    if ImageFormat.importableExtensions.contains(child.pathExtension.lowercased()) {
                        files.append(child)
                    }
                }
                files.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                result.append(contentsOf: files.map { DiscoveredFile(url: $0, root: url) })
            } else if ImageFormat.importableExtensions.contains(url.pathExtension.lowercased()) {
                result.append(DiscoveredFile(url: url, root: nil))
            }
        }
        return result
    }

    /// Analyses files a few at a time so a 1 000-file import never loads everything at once.
    private func analyze(_ newItems: [QueueItem]) async {
        let thumbnailSize = preferences.values.thumbnailPixelSize
        await withTaskGroup(of: Void.self) { group in
            var iterator = newItems.makeIterator()
            var inFlight = 0
            func startNext() -> Bool {
                guard let item = iterator.next() else { return false }
                let url = item.url
                group.addTask { @MainActor in
                    let outcome = await Task.detached(priority: .utility) { () -> Result<(ImageAnalysis, CGImage?), Error> in
                        autoreleasepool {
                            do {
                                let analysis = try ImageAnalyzer().analyze(url: url)
                                let thumbnail = ThumbnailLoader.thumbnail(for: analysis, pixelSize: thumbnailSize)
                                return .success((analysis, thumbnail))
                            } catch {
                                return .failure(error)
                            }
                        }
                    }.value
                    switch outcome {
                    case .success(let (analysis, thumbnail)):
                        item.analysis = analysis
                        item.thumbnail = thumbnail
                        item.status = .ready
                    case .failure(let error):
                        let message = (error as? LocalizedError).map { [$0.errorDescription, $0.recoverySuggestion].compactMap { $0 }.joined(separator: " ") } ?? error.localizedDescription
                        item.status = .unreadable(message)
                    }
                }
                return true
            }
            while inFlight < 4, startNext() { inFlight += 1 }
            for await _ in group {
                if !startNext() { inFlight -= 1 }
            }
        }
    }

    // MARK: - Queue editing

    func remove(_ ids: Set<QueueItem.ID>) {
        guard !isProcessing else { return }
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    func removeSelected() { remove(selection) }

    func clearQueue() {
        guard !isProcessing else { return }
        items.removeAll()
        selection.removeAll()
        duplicateNotice = nil
        preview.clear()
    }

    func selectAll() { selection = Set(items.map(\.id)) }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealLastExport() {
        if let folder = lastOutputFolders.first {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }

    // MARK: - Settings and presets

    func apply(_ preset: Preset) {
        preset.apply(to: &settings)
    }

    func resetSettings() {
        let output = settings.output
        settings = .default
        settings.output = output
    }

    func promptForPresetName() {
        presetNameDraft = presets.uniqueName("My preset")
        presetNamePrompt = true
    }

    func savePresetFromPrompt() {
        presets.add(name: presetNameDraft, settings: settings)
        presetNamePrompt = false
    }

    func chooseCustomOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Optimized images will be saved in this folder."
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.folderAccess.grant(url)
            self.settings.output.customFolderBookmark = try? SecurityScopedAccess.bookmark(for: url)
            self.settings.output.customFolderPath = url.path
            self.settings.output.destination = .customFolder
        }
    }

    // MARK: - Export

    func export() {
        guard !isProcessing else { return }
        let candidates = readyItems
        guard !candidates.isEmpty else {
            alert = AlertMessage(title: "Nothing to export", message: "Add images to the queue first.")
            return
        }
        if let problem = settingsProblem {
            alert = AlertMessage(title: "Check your settings", message: problem)
            return
        }
        var customFolder: URL?
        if settings.resolvedForProcessing.output.destination == .customFolder {
            guard let url = folderAccess.resolve(bookmark: settings.output.customFolderBookmark) else {
                alert = AlertMessage(title: "Output folder unavailable", message: "The chosen output folder could not be found. Pick it again in the Output section.")
                return
            }
            customFolder = url
        }
        let batchItems = candidates.compactMap { item in item.job.map { BatchItem(id: item.id, job: $0) } }
        let context = PipelineContext(settings: settings, capabilities: capabilities, acknowledgedWarnings: [], customFolderURL: customFolder)
        let report = PreflightReport.make(items: batchItems, context: context)
        if !report.unavailableEncoders.isEmpty {
            let names = report.unavailableEncoders.map(\.displayName).sorted().joined(separator: ", ")
            alert = AlertMessage(title: "Encoder not available", message: "This Mac cannot encode \(names). Choose a different format.")
            return
        }
        pendingExport = PendingExport(items: batchItems, context: context, report: report)
        let needsOverwriteConfirmation = settings.output.conflictPolicy == .overwrite
        if report.confirmations.isEmpty && !needsOverwriteConfirmation {
            Task { await startPendingExport() }
        } else {
            let warnings = report.confirmations
                .map { (warning: $0.key, count: $0.value) }
                .sorted { $0.warning.title < $1.warning.title }
            pendingConfirmation = ConfirmationRequest(warnings: warnings, overwriteWarning: needsOverwriteConfirmation, total: batchItems.count)
        }
    }

    func confirmPendingExport() {
        guard var pending = pendingExport else { return }
        pending.context.acknowledgedWarnings = Set(pending.report.confirmations.keys)
        pendingExport = pending
        pendingConfirmation = nil
        Task { await startPendingExport() }
    }

    func cancelPendingExport() {
        pendingConfirmation = nil
        pendingExport = nil
    }

    private func startPendingExport() async {
        guard let pending = pendingExport else { return }
        pendingExport = nil

        // Sandbox: make sure every destination folder is writable before starting.
        for folder in pending.report.destinationFolders where !SecurityScopedAccess.canWrite(to: folder) {
            let granted = await folderAccess.requestAccess(to: folder)
            if !granted {
                alert = AlertMessage(title: "Export cancelled", message: "Without access to “\(folder.lastPathComponent)” the optimized files cannot be saved there. Choose a different destination in the Output section or grant access.")
                return
            }
        }

        let ids = Set(pending.items.map(\.id))
        for item in items where ids.contains(item.id) { item.resetForProcessing() }
        isProcessing = true
        isPaused = false
        progressCompleted = 0
        progressTotal = pending.items.count
        lastSummary = nil
        lastOutputFolders = pending.report.destinationFolders

        let processor = BatchProcessor(maxConcurrency: preferences.values.maxConcurrency)
        self.processor = processor
        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for await event in processor.run(items: pending.items, context: pending.context) {
            switch event {
            case .itemStarted(let id):
                lookup[id]?.status = .processing
            case .itemFinished(let id, let result):
                lookup[id]?.apply(result)
            case .progress(let completed, _):
                progressCompleted = completed
            case .finished(let summary):
                lastSummary = summary
            }
        }
        // Items never started (cancelled before their turn) go back to ready.
        for item in items where item.status == .queued { item.status = .ready }
        self.processor = nil
        isProcessing = false
        isPaused = false
        if let summary = lastSummary {
            if preferences.values.showSummaryAfterExport && !summary.wasCancelled { showSummary = true }
            if preferences.values.revealInFinderAfterExport, summary.succeeded > 0, let folder = lastOutputFolders.first {
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            }
        }
        if let selected = selectedItem { preview.update(item: selected, settings: settings, capabilities: capabilities) }
    }

    func cancel() {
        processor?.cancel()
        isPaused = false
    }

    func togglePause() {
        guard let processor else { return }
        if isPaused {
            processor.resume()
            isPaused = false
        } else {
            processor.pause()
            isPaused = true
        }
    }

    // MARK: - Preview

    func refreshPreview() {
        preview.update(item: selectedItem, settings: settings, capabilities: capabilities)
    }
}

/// Small upright thumbnails for the queue.
enum ThumbnailLoader {
    nonisolated static func thumbnail(for analysis: ImageAnalysis, pixelSize: Int) -> CGImage? {
        if analysis.format == .svg {
            let plan = Resizer.plan(source: analysis.pixelSize, settings: ResizeSettings(mode: .fit, width: pixelSize, height: pixelSize, onlyShrink: false))
            return try? SVGRasterizer.rasterize(url: analysis.url, size: plan.outputSize)
        }
        guard let source = try? ImageDecoder.makeSource(url: analysis.url) else { return nil }
        return try? ImageDecoder.decodeFrame(source, maxPixelSize: pixelSize)
    }
}
