import Foundation
import CoreGraphics
import Observation
import OptimizerCore

enum QueueViewMode: String, CaseIterable, Identifiable {
    case list, grid
    var id: String { rawValue }
}

/// One file in the queue. Observable so rows update as analysis and processing progress.
@Observable @MainActor
final class QueueItem: Identifiable {
    enum Status: Equatable {
        case analyzing
        case ready
        case unreadable(String)
        case queued
        case processing
        case done
        case keptOriginal
        case skipped(String)
        case failed(String)

        var label: String {
            switch self {
            case .analyzing: return "Analyzing…"
            case .ready: return "Ready"
            case .unreadable: return "Cannot read"
            case .queued: return "Waiting"
            case .processing: return "Optimizing…"
            case .done: return "Done"
            case .keptOriginal: return "Kept original"
            case .skipped(let reason): return "Skipped: \(reason)"
            case .failed: return "Failed"
            }
        }

        var symbolName: String {
            switch self {
            case .analyzing, .processing: return "arrow.triangle.2.circlepath"
            case .ready: return "circle"
            case .unreadable, .failed: return "exclamationmark.triangle.fill"
            case .queued: return "clock"
            case .done: return "checkmark.circle.fill"
            case .keptOriginal: return "equal.circle.fill"
            case .skipped: return "minus.circle.fill"
            }
        }

        var isBusy: Bool {
            switch self {
            case .analyzing, .queued, .processing: return true
            default: return false
            }
        }

        var isFinished: Bool {
            switch self {
            case .done, .keptOriginal, .skipped, .failed: return true
            default: return false
            }
        }
    }

    nonisolated let id = UUID()
    nonisolated let url: URL
    nonisolated let importRoot: URL?
    var analysis: ImageAnalysis?
    var thumbnail: CGImage?
    var status: Status = .analyzing
    var result: ProcessingResult?

    init(url: URL, importRoot: URL?) {
        self.url = url
        self.importRoot = importRoot
    }

    nonisolated var name: String { url.lastPathComponent }

    var canProcess: Bool { analysis != nil && !status.isBusy }

    var job: ProcessingJob? {
        guard let analysis else { return nil }
        return ProcessingJob(sourceURL: url, importRoot: importRoot, analysis: analysis)
    }

    func apply(_ result: ProcessingResult) {
        self.result = result
        switch result.status {
        case .success: status = .done
        case .keptOriginal: status = .keptOriginal
        case .skipped(let reason): status = .skipped(reason)
        case .failed(let message): status = .failed(message)
        }
    }

    /// Clears a previous run so the file can be processed again.
    func resetForProcessing() {
        result = nil
        status = analysis == nil ? status : .queued
    }
}
