import CoreGraphics
import Foundation
import Observation
import OptimizerCore

/// Renders the selected image with the current settings in the background so the inspector
/// can show a before/after comparison and the exact output size before exporting.
@Observable @MainActor
final class PreviewModel {
    /// Longest side of decoded preview bitmaps; keeps memory bounded for huge images.
    nonisolated static let maxPreviewPixels = 4096

    private(set) var original: CGImage?
    private(set) var optimized: CGImage?
    private(set) var estimatedSize: Int64?
    private(set) var outputSize: PixelSize?
    private(set) var plan: ItemPlan?
    private(set) var isRendering = false
    private(set) var errorMessage: String?
    private(set) var notes: [String] = []
    private(set) var itemID: QueueItem.ID?

    private var task: Task<Void, Never>?

    func clear() {
        task?.cancel()
        task = nil
        original = nil
        optimized = nil
        estimatedSize = nil
        outputSize = nil
        plan = nil
        notes = []
        errorMessage = nil
        isRendering = false
        itemID = nil
    }

    func update(item: QueueItem?, settings: OptimizationSettings, capabilities: EncoderCapabilities) {
        task?.cancel()
        guard let item, let job = item.job else {
            clear()
            return
        }
        if itemID != item.id {
            original = nil
            optimized = nil
            estimatedSize = nil
        }
        itemID = item.id
        let context = PipelineContext(settings: settings, capabilities: capabilities,
                                      acknowledgedWarnings: Set(ItemWarning.allCases))
        let plan = OptimizationPipeline.plan(for: job, context: context)
        self.plan = plan
        outputSize = plan.outputSize
        errorMessage = nil
        isRendering = true

        task = Task { [weak self] in
            // Debounce slider drags.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<PreviewOutcome, Error> in
                do {
                    let encoded = try OptimizationPipeline.encode(job: job, plan: plan, context: context)
                    let optimizedImage = try ImageDecoder.decodeFrame(ImageDecoder.makeSource(data: encoded.data),
                                                                      maxPixelSize: PreviewModel.maxPreviewPixels)
                    let originalImage: CGImage
                    if job.analysis.format == .svg {
                        originalImage = try SVGRasterizer.rasterize(url: job.sourceURL, size: encoded.outputSize)
                    } else {
                        let limit = min(PreviewModel.maxPreviewPixels, encoded.outputSize.longestSide)
                        originalImage = try ImageDecoder.decodeFrame(ImageDecoder.makeSource(url: job.sourceURL), maxPixelSize: limit)
                    }
                    return .success(PreviewOutcome(original: originalImage, optimized: optimizedImage,
                                                   size: Int64(encoded.data.count), outputSize: encoded.outputSize, notes: encoded.notes))
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            switch outcome {
            case .success(let preview):
                self.original = preview.original
                self.optimized = preview.optimized
                self.estimatedSize = preview.size
                self.outputSize = preview.outputSize
                self.notes = preview.notes
            case .failure(let error):
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            self.isRendering = false
        }
    }
}

struct PreviewOutcome {
    var original: CGImage
    var optimized: CGImage
    var size: Int64
    var outputSize: PixelSize
    var notes: [String]
}
