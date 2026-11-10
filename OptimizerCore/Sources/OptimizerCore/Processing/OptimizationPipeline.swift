import Foundation
import ImageIO
import CoreGraphics

/// One source file plus what the analyzer learned about it.
public struct ProcessingJob: Sendable, Hashable {
    public var sourceURL: URL
    /// Folder the file was imported from (for preserving folder structure), if any.
    public var importRoot: URL?
    public var analysis: ImageAnalysis

    public init(sourceURL: URL, importRoot: URL? = nil, analysis: ImageAnalysis) {
        self.sourceURL = sourceURL
        self.importRoot = importRoot
        self.analysis = analysis
    }
}

/// Everything the pipeline needs besides the job itself.
public struct PipelineContext: Sendable {
    public var settings: OptimizationSettings
    public var capabilities: EncoderCapabilities
    /// Warnings the user has already confirmed for this batch.
    public var acknowledgedWarnings: Set<ItemWarning>
    /// Resolved custom output folder (the app resolves the bookmark).
    public var customFolderURL: URL?

    public init(settings: OptimizationSettings, capabilities: EncoderCapabilities = .current,
                acknowledgedWarnings: Set<ItemWarning> = [], customFolderURL: URL? = nil) {
        self.settings = settings
        self.capabilities = capabilities
        self.acknowledgedWarnings = acknowledgedWarnings
        self.customFolderURL = customFolderURL
    }
}

/// What will happen to one file. Computed instantly so the UI can show it before exporting.
public struct ItemPlan: Sendable, Hashable {
    public var outputFormat: OutputFormat
    public var lossless: Bool
    public var quality: Int
    public var resize: ResizePlan
    public var preserveAnimation: Bool
    public var convertToSRGB: Bool
    public var keepAlpha: Bool
    public var warnings: [ItemWarning]
    public var decisions: [String]

    public var requiredConfirmations: [ItemWarning] { warnings.filter(\.requiresConfirmation) }
    public var outputSize: PixelSize { resize.outputSize }
}

public enum OptimizationPipeline {
    // MARK: Planning

    public static func plan(for job: ProcessingJob, context: PipelineContext) -> ItemPlan {
        let settings = context.settings.resolvedForProcessing
        let analysis = job.analysis
        var decisions: [String] = []
        var warnings: [ItemWarning] = []

        // 1. Format
        var format: OutputFormat
        var lossless: Bool
        switch settings.format {
        case .auto:
            let input = FormatSelector.Input(analysis: analysis, capabilities: context.capabilities,
                                             allowAVIF: settings.auto.allowsAVIF, compatibilityMode: settings.auto.compatibilityMode)
            let decision = FormatSelector.decide(input)
            format = decision.format
            lossless = decision.lossless
            decisions.append(decision.reason)
        case .original:
            format = analysis.format.closestOutputFormat
            if !context.capabilities.supports(format) {
                decisions.append("\(format.displayName) cannot be encoded on this Mac; using WebP instead.")
                format = .webp
            } else {
                decisions.append("Kept the original \(format.displayName) format.")
            }
            lossless = settings.quality.lossless
        default:
            format = settings.format.fixedFormat ?? .webp
            lossless = settings.quality.lossless
        }
        if !format.supportsLossless {
            if lossless && format.usesQualitySlider { warnings.append(.losslessNotSupported) }
            lossless = !format.usesQualitySlider // PNG/GIF are inherently lossless
        }
        let quality = settings.quality.quality

        // 2. Geometry
        var resize = Resizer.plan(source: analysis.pixelSize, settings: settings.resize)
        if analysis.format == .svg {
            warnings.append(.svgRasterized)
            if resize.isNoOp {
                decisions.append("SVG rendered at its intrinsic size \(analysis.pixelSize). Set a size in Resize for a larger render.")
            } else {
                decisions.append("SVG rendered at \(resize.outputSize).")
            }
            // Vector sources may be rendered larger without loss.
            if resize.isEnlarging { resize.isEnlarging = false }
        } else if !resize.isNoOp {
            decisions.append("Resized \(analysis.pixelSize) → \(resize.outputSize)" + (resize.note.map { " (\($0.lowercased().dropLast()))" } ?? "") + ".")
        } else if let note = resize.note {
            decisions.append(note)
        }
        if resize.isEnlarging { warnings.append(.willEnlarge) }
        if analysis.isOriented { decisions.append("EXIF orientation \(analysis.orientation) applied; pixels are stored upright.") }

        // 3. Animation and transparency
        let preserveAnimation = analysis.isAnimated && format.supportsAnimation
        if analysis.isAnimated {
            if preserveAnimation {
                decisions.append("Animation kept: \(analysis.frameCount) frames.")
            } else {
                warnings.append(.willFlattenAnimation)
            }
        }
        let keepAlpha = analysis.usesTransparency && format.supportsTransparency
        if analysis.usesTransparency && !format.supportsTransparency {
            warnings.append(.willLoseTransparency)
        } else if analysis.usesTransparency {
            decisions.append("Transparency preserved.")
        }

        // 4. Quality
        if format.usesQualitySlider {
            if lossless {
                decisions.append("Lossless \(format.displayName).")
            } else {
                decisions.append("\(format.displayName) quality \(quality)" + (format == .jpeg && settings.quality.progressiveJPEG ? ", progressive." : "."))
                switch QualitySettings.artifactRisk(quality: quality, format: format, lossless: lossless) {
                case .likely: warnings.append(.lowQualityArtifacts)
                case .possible: decisions.append("Slight artifacts possible at this quality.")
                case .none: break
                }
            }
            if analysis.isLikelyAlreadyCompressed && !lossless && analysis.format == format.imageFormat {
                warnings.append(.alreadyCompressed)
            }
        } else if format == .png {
            decisions.append(settings.quality.optimizePNGPalette ? "Lossless PNG with palette optimisation." : "Lossless PNG.")
        }

        // 5. Colour and metadata
        let convertToSRGB = settings.metadata.effectiveConvertToSRGB && !analysis.isSRGB && analysis.format != .svg
        if convertToSRGB {
            decisions.append("Converted \(analysis.colorSpaceName ?? "embedded profile") → sRGB.")
        } else if !analysis.isSRGB, let name = analysis.colorSpaceName, analysis.format != .svg {
            decisions.append("Kept the \(name) profile embedded.")
        }
        switch settings.metadata.policy {
        case .removeAll: decisions.append("All metadata removed.")
        case .colorProfileOnly: decisions.append("Metadata removed; colour profile kept.")
        case .copyrightOnly: decisions.append("Only copyright and author metadata kept.")
        case .keepAll: decisions.append(settings.metadata.stripGPS ? "Metadata kept except GPS location." : "All metadata kept, including GPS.")
        }
        if format == .webp && settings.metadata.policy == .keepAll && analysis.hasEXIF {
            warnings.append(.metadataPartiallyUnsupported)
        }
        if settings.output.destination == .replaceOriginals { warnings.append(.replaceOriginal) }

        return ItemPlan(outputFormat: format, lossless: lossless, quality: quality, resize: resize,
                        preserveAnimation: preserveAnimation, convertToSRGB: convertToSRGB, keepAlpha: keepAlpha,
                        warnings: warnings, decisions: decisions)
    }

    // MARK: Encoding (in memory)

    public struct EncodeOutcome {
        public var data: Data
        public var outputSize: PixelSize
        public var notes: [String]
    }

    /// Decodes, resizes, converts and encodes without touching the disk. Used for exports and previews.
    public static func encode(job: ProcessingJob, plan: ItemPlan, context: PipelineContext) throws -> EncodeOutcome {
        let settings = context.settings.resolvedForProcessing
        guard context.capabilities.supports(plan.outputFormat) else { throw OptimizerError.encoderUnavailable(plan.outputFormat) }
        let analysis = job.analysis
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

        var frames: [CGImage] = []
        var delays: [Double] = []
        var loopCount = 0
        var metadata: CGImageMetadata?
        var iccProfile: Data?

        if analysis.format == .svg {
            frames = [try SVGRasterizer.rasterize(url: job.sourceURL, size: plan.resize.outputSize)]
        } else {
            let source = try ImageDecoder.makeSource(url: job.sourceURL)
            let frameCount = CGImageSourceGetCount(source)
            let indices = plan.preserveAnimation ? Array(0..<frameCount) : [0]
            if plan.preserveAnimation {
                delays = ImageDecoder.frameDelays(source)
                loopCount = ImageDecoder.loopCount(source)
            }
            // Decode no larger than the drawn size: for fit/exact that is the output, for fill it is the scaled source.
            let decodeLimit: Int? = plan.resize.isNoOp ? nil : Int(ceil(max(plan.resize.drawRect.width, plan.resize.drawRect.height)))

            for index in indices {
                try Task.checkCancellation()
                let decoded = try ImageDecoder.decodeFrame(source, index: index, maxPixelSize: decodeLimit)
                let targetSpace: CGColorSpace
                if plan.convertToSRGB || decoded.colorSpace == nil || decoded.colorSpace?.model != .rgb {
                    targetSpace = sRGB
                } else {
                    targetSpace = decoded.colorSpace!
                }
                let needsRender = decoded.width != plan.resize.outputSize.width
                    || decoded.height != plan.resize.outputSize.height
                    || (decoded.colorSpace.map { $0 != targetSpace } ?? true)
                    || decoded.bitsPerComponent != 8
                    || (!plan.keepAlpha && decoded.alphaInfo != .none && decoded.alphaInfo != .noneSkipLast && decoded.alphaInfo != .noneSkipFirst)
                    || settings.resize.sharpenAfterResize
                let frame: CGImage
                if needsRender {
                    let options = Resizer.RenderOptions(keepAlpha: plan.keepAlpha, colorSpace: targetSpace,
                                                        sharpen: settings.resize.sharpenAfterResize && !plan.resize.isNoOp)
                    frame = try Resizer.render(decoded, plan: plan.resize, options: options)
                } else {
                    frame = decoded
                }
                if index == indices.first {
                    metadata = MetadataFilter.destinationMetadata(from: source, index: 0, settings: settings.metadata, outputSize: plan.resize.outputSize)
                    if !plan.convertToSRGB { iccProfile = ImageDecoder.iccProfile(for: frame.colorSpace) }
                }
                frames.append(frame)
            }
        }
        guard let first = frames.first else { throw OptimizerError.corrupted(job.sourceURL) }

        let options = EncodeOptions(format: plan.outputFormat, quality: plan.quality, lossless: plan.lossless,
                                    progressiveJPEG: settings.quality.progressiveJPEG, effort: settings.quality.effort,
                                    optimizePNGPalette: settings.quality.optimizePNGPalette,
                                    frameDelays: delays, loopCount: loopCount, iccProfile: iccProfile)
        let encoded = try ImageEncoder.encode(frames: frames, options: options, metadata: metadata)
        return EncodeOutcome(data: encoded.data, outputSize: PixelSize(width: first.width, height: first.height), notes: encoded.notes)
    }

    // MARK: Full processing (encode + write)

    public static func process(job: ProcessingJob, context: PipelineContext, namer: OutputNamer, registry: NameRegistry,
                               fileManager: FileManager = .default) -> ProcessingResult {
        let start = Date()
        let plan = plan(for: job, context: context)
        let analysis = job.analysis

        func result(_ status: ProcessingResult.Status, outputURL: URL?, optimizedSize: Int64, outputSize: PixelSize, extraDecisions: [String] = []) -> ProcessingResult {
            ProcessingResult(sourceURL: job.sourceURL, outputURL: outputURL, originalSize: analysis.fileSize, optimizedSize: optimizedSize,
                             originalPixelSize: analysis.pixelSize, outputPixelSize: outputSize,
                             inputFormat: analysis.format, outputFormat: plan.outputFormat,
                             decisions: plan.decisions + extraDecisions, warnings: plan.warnings, status: status,
                             duration: Date().timeIntervalSince(start))
        }

        if let pending = plan.requiredConfirmations.first(where: { !context.acknowledgedWarnings.contains($0) }) {
            return result(.skipped(reason: pending.title), outputURL: nil, optimizedSize: analysis.fileSize, outputSize: analysis.pixelSize)
        }

        do {
            try Task.checkCancellation()
            let outcome = try encode(job: job, plan: plan, context: context)
            var data = outcome.data
            var decisions = outcome.notes
            var status: ProcessingResult.Status = .success
            let settings = context.settings.resolvedForProcessing

            // Never make a file bigger when nothing else changed.
            if settings.output.keepOriginalIfLarger
                && Int64(data.count) >= analysis.fileSize
                && plan.outputFormat.imageFormat == analysis.format
                && plan.resize.isNoOp {
                decisions.append("Re-encoding gave \(ByteFormatting.string(Int64(data.count))) versus \(ByteFormatting.string(analysis.fileSize)) originally, so the original bytes were kept.")
                data = try Data(contentsOf: job.sourceURL)
                status = .keptOriginal
                if settings.output.destination == .replaceOriginals {
                    return result(.keptOriginal, outputURL: job.sourceURL, optimizedSize: analysis.fileSize, outputSize: analysis.pixelSize, extraDecisions: decisions)
                }
            }

            let folder = try namer.destinationFolder(for: job.sourceURL, importRoot: job.importRoot)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            guard SecurityScopedAccess.canWrite(to: folder) else { throw OptimizerError.destinationNotWritable(folder) }
            let proposed = folder.appendingPathComponent(namer.fileName(for: job.sourceURL, format: plan.outputFormat))

            let outputURL: URL
            switch namer.resolve(proposed: proposed, source: job.sourceURL, registry: registry, fileManager: fileManager) {
            case .skip(let reason):
                return result(.skipped(reason: reason), outputURL: nil, optimizedSize: analysis.fileSize, outputSize: analysis.pixelSize)
            case .replaceSource(let url):
                try Task.checkCancellation()
                try writeReplacing(data: data, at: url, fileManager: fileManager)
                outputURL = url
                decisions.append("Original replaced in place.")
            case .write(let url):
                try Task.checkCancellation()
                try data.write(to: url, options: .atomic)
                outputURL = url
                if settings.output.destination == .replaceOriginals {
                    // Format changed: the new file sits beside the original, which goes to the Trash.
                    do {
                        try fileManager.trashItem(at: job.sourceURL, resultingItemURL: nil)
                        decisions.append("Original moved to the Trash.")
                    } catch {
                        decisions.append("Original could not be moved to the Trash and was left in place.")
                    }
                }
            }

            do {
                try OutputValidator.validate(url: outputURL)
            } catch {
                try? fileManager.removeItem(at: outputURL)
                throw error
            }
            decisions.append("Output verified: file opens correctly.")
            return result(status, outputURL: outputURL, optimizedSize: Int64(data.count), outputSize: outcome.outputSize, extraDecisions: decisions)
        } catch is CancellationError {
            return result(.skipped(reason: "Cancelled"), outputURL: nil, optimizedSize: analysis.fileSize, outputSize: analysis.pixelSize)
        } catch let error as OptimizerError {
            if error == .cancelled {
                return result(.skipped(reason: "Cancelled"), outputURL: nil, optimizedSize: analysis.fileSize, outputSize: analysis.pixelSize)
            }
            let message = [error.errorDescription, error.recoverySuggestion].compactMap { $0 }.joined(separator: " ")
            return result(.failed(message: message), outputURL: nil, optimizedSize: analysis.fileSize, outputSize: analysis.pixelSize)
        } catch {
            return result(.failed(message: error.localizedDescription), outputURL: nil, optimizedSize: analysis.fileSize, outputSize: analysis.pixelSize)
        }
    }

    /// Writes to a temporary file in the same folder, then swaps it in so a crash cannot leave a half-written original.
    static func writeReplacing(data: Data, at url: URL, fileManager: FileManager) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        do {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary, backupItemName: nil, options: [])
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }
}

/// Aggregated information about a batch before it runs.
public struct PreflightReport: Sendable {
    public var plans: [UUID: ItemPlan]
    /// How many items need each confirmation.
    public var confirmations: [ItemWarning: Int]
    /// Folders that will receive files.
    public var destinationFolders: [URL]
    public var unavailableEncoders: Set<OutputFormat>

    public static func make(items: [BatchItem], context: PipelineContext) -> PreflightReport {
        var plans: [UUID: ItemPlan] = [:]
        var confirmations: [ItemWarning: Int] = [:]
        var folders = Set<URL>()
        var unavailable = Set<OutputFormat>()
        let namer = OutputNamer(settings: context.settings.resolvedForProcessing.output, customFolder: context.customFolderURL)
        for item in items {
            let plan = OptimizationPipeline.plan(for: item.job, context: context)
            plans[item.id] = plan
            for warning in plan.requiredConfirmations { confirmations[warning, default: 0] += 1 }
            if !context.capabilities.supports(plan.outputFormat) { unavailable.insert(plan.outputFormat) }
            if let folder = try? namer.destinationFolder(for: item.job.sourceURL, importRoot: item.job.importRoot) {
                folders.insert(folder.standardizedFileURL)
            }
        }
        return PreflightReport(plans: plans, confirmations: confirmations,
                               destinationFolders: folders.sorted { $0.path < $1.path }, unavailableEncoders: unavailable)
    }
}
