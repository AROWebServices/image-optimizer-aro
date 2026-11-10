import Foundation

/// Conditions the user should know about before or after processing a file.
public enum ItemWarning: String, Codable, Sendable, Hashable, CaseIterable {
    case willFlattenAnimation
    case willLoseTransparency
    case willEnlarge
    case lowQualityArtifacts
    case alreadyCompressed
    case replaceOriginal
    case svgRasterized
    case metadataPartiallyUnsupported
    case losslessNotSupported

    /// Warnings that must be acknowledged before the batch starts.
    public var requiresConfirmation: Bool {
        switch self {
        case .willFlattenAnimation, .willLoseTransparency, .replaceOriginal, .alreadyCompressed: return true
        default: return false
        }
    }

    public var title: String {
        switch self {
        case .willFlattenAnimation: return "Animation will be flattened"
        case .willLoseTransparency: return "Transparency will be lost"
        case .willEnlarge: return "Image will be enlarged"
        case .lowQualityArtifacts: return "Visible compression artifacts likely"
        case .alreadyCompressed: return "Already heavily compressed"
        case .replaceOriginal: return "Original will be replaced"
        case .svgRasterized: return "SVG will be rasterized"
        case .metadataPartiallyUnsupported: return "Some metadata cannot be stored"
        case .losslessNotSupported: return "Lossless not available"
        }
    }

    public var detail: String {
        switch self {
        case .willFlattenAnimation: return "The output format cannot store animation, so only the first frame will be kept."
        case .willLoseTransparency: return "JPEG has no alpha channel. Transparent areas will be filled with white."
        case .willEnlarge: return "The requested size is larger than the source. Enlarging adds no detail and increases file size."
        case .lowQualityArtifacts: return "Raise the quality or pick a different preset if sharp detail matters."
        case .alreadyCompressed: return "Recompressing a heavily compressed file degrades it further and rarely saves much."
        case .replaceOriginal: return "The source file will be moved to the Trash and replaced by the optimized version."
        case .svgRasterized: return "Vector files are rendered to pixels at the chosen size. Keep the SVG for scalable use."
        case .metadataPartiallyUnsupported: return "WebP stores color profiles and XMP but not EXIF; some tags are dropped."
        case .losslessNotSupported: return "This encoder has no lossless mode; the highest lossy quality is used instead."
        }
    }
}

public struct ProcessingResult: Sendable, Hashable, Codable {
    public enum Status: Sendable, Hashable, Codable {
        case success
        /// Output would have been larger; the original bytes were kept.
        case keptOriginal
        case skipped(reason: String)
        case failed(message: String)

        public var isSuccess: Bool {
            switch self {
            case .success, .keptOriginal: return true
            default: return false
            }
        }

        public var displayName: String {
            switch self {
            case .success: return "Done"
            case .keptOriginal: return "Kept original"
            case .skipped: return "Skipped"
            case .failed: return "Failed"
            }
        }
    }

    public var sourceURL: URL
    public var outputURL: URL?
    public var originalSize: Int64
    public var optimizedSize: Int64
    public var originalPixelSize: PixelSize
    public var outputPixelSize: PixelSize
    public var inputFormat: ImageFormat
    public var outputFormat: OutputFormat
    public var decisions: [String]
    public var warnings: [ItemWarning]
    public var status: Status
    public var duration: TimeInterval

    public init(sourceURL: URL, outputURL: URL?, originalSize: Int64, optimizedSize: Int64,
                originalPixelSize: PixelSize, outputPixelSize: PixelSize,
                inputFormat: ImageFormat, outputFormat: OutputFormat,
                decisions: [String], warnings: [ItemWarning], status: Status, duration: TimeInterval) {
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.originalSize = originalSize
        self.optimizedSize = optimizedSize
        self.originalPixelSize = originalPixelSize
        self.outputPixelSize = outputPixelSize
        self.inputFormat = inputFormat
        self.outputFormat = outputFormat
        self.decisions = decisions
        self.warnings = warnings
        self.status = status
        self.duration = duration
    }

    public var bytesSaved: Int64 { originalSize - optimizedSize }

    /// Positive numbers mean the file got smaller.
    public var reductionPercent: Double {
        guard originalSize > 0 else { return 0 }
        return (1 - Double(optimizedSize) / Double(originalSize)) * 100
    }
}

public struct BatchSummary: Sendable, Hashable, Codable {
    public var processed: Int
    public var succeeded: Int
    public var keptOriginal: Int
    public var failed: Int
    public var skipped: Int
    public var totalOriginalSize: Int64
    public var totalOptimizedSize: Int64
    public var duration: TimeInterval
    public var wasCancelled: Bool

    public init(results: [ProcessingResult], duration: TimeInterval, wasCancelled: Bool) {
        processed = results.count
        succeeded = results.filter { $0.status == .success }.count
        keptOriginal = results.filter { $0.status == .keptOriginal }.count
        failed = results.filter { if case .failed = $0.status { return true } else { return false } }.count
        skipped = results.filter { if case .skipped = $0.status { return true } else { return false } }.count
        let counted = results.filter { $0.status.isSuccess }
        totalOriginalSize = counted.reduce(0) { $0 + $1.originalSize }
        totalOptimizedSize = counted.reduce(0) { $0 + $1.optimizedSize }
        self.duration = duration
        self.wasCancelled = wasCancelled
    }

    public var totalSaved: Int64 { totalOriginalSize - totalOptimizedSize }

    public var averageReductionPercent: Double {
        guard totalOriginalSize > 0 else { return 0 }
        return (1 - Double(totalOptimizedSize) / Double(totalOriginalSize)) * 100
    }
}
