import Foundation

public struct BatchItem: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let job: ProcessingJob

    public init(id: UUID, job: ProcessingJob) {
        self.id = id
        self.job = job
    }
}

public enum BatchEvent: Sendable {
    case itemStarted(UUID)
    case itemFinished(UUID, ProcessingResult)
    case progress(completed: Int, total: Int)
    case finished(BatchSummary)
}

/// Lets queued work wait while the batch is paused. `pause()` takes effect synchronously so
/// no further item starts after the call returns; items already encoding finish normally.
final class PauseGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isPaused = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func pause() {
        lock.lock()
        isPaused = true
        lock.unlock()
    }

    func resume() {
        lock.lock()
        isPaused = false
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    private func checkPaused() -> Bool {
        lock.withLock { isPaused }
    }

    /// Returns true when the continuation was parked, false when the gate was already open.
    private func park(_ continuation: CheckedContinuation<Void, Never>) -> Bool {
        lock.withLock {
            guard isPaused else { return false }
            waiters.append(continuation)
            return true
        }
    }

    func waitWhilePaused() async {
        while checkPaused() {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if !park(continuation) { continuation.resume() }
            }
        }
    }
}

/// Processes a queue with bounded parallelism. Each item runs in its own autorelease pool so
/// decoded bitmaps are freed as soon as the file is written, keeping memory flat for big batches.
public final class BatchProcessor: @unchecked Sendable {
    public static var defaultConcurrency: Int {
        min(4, max(1, ProcessInfo.processInfo.activeProcessorCount / 2))
    }

    private let maxConcurrency: Int
    private let gate = PauseGate()
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    public init(maxConcurrency: Int = BatchProcessor.defaultConcurrency) {
        self.maxConcurrency = max(1, maxConcurrency)
    }

    public func run(items: [BatchItem], context: PipelineContext) -> AsyncStream<BatchEvent> {
        AsyncStream { continuation in
            let gate = self.gate
            let concurrency = self.maxConcurrency
            let task = Task.detached(priority: .userInitiated) {
                let start = Date()
                var results: [ProcessingResult] = []
                let settings = context.settings.resolvedForProcessing
                let registry = NameRegistry(protectedSources: items.map(\.job.sourceURL))
                let namer = OutputNamer(settings: settings.output, customFolder: context.customFolderURL)

                await withTaskGroup(of: (UUID, ProcessingResult).self) { group in
                    var iterator = items.makeIterator()
                    var completed = 0

                    @discardableResult
                    func startNext() -> Bool {
                        guard !Task.isCancelled, let item = iterator.next() else { return false }
                        group.addTask {
                            await gate.waitWhilePaused()
                            if Task.isCancelled {
                                return (item.id, BatchProcessor.cancelledResult(for: item.job))
                            }
                            continuation.yield(.itemStarted(item.id))
                            let result = autoreleasepool {
                                OptimizationPipeline.process(job: item.job, context: context, namer: namer, registry: registry)
                            }
                            return (item.id, result)
                        }
                        return true
                    }

                    for _ in 0..<concurrency { if !startNext() { break } }
                    for await (id, result) in group {
                        results.append(result)
                        completed += 1
                        continuation.yield(.itemFinished(id, result))
                        continuation.yield(.progress(completed: completed, total: items.count))
                        startNext()
                    }
                }
                let summary = BatchSummary(results: results, duration: Date().timeIntervalSince(start), wasCancelled: Task.isCancelled)
                continuation.yield(.finished(summary))
                continuation.finish()
            }
            self.lock.lock()
            self.task = task
            self.lock.unlock()
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func cancel() {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
        gate.resume()
    }

    public func pause() {
        gate.pause()
    }

    public func resume() {
        gate.resume()
    }

    static func cancelledResult(for job: ProcessingJob) -> ProcessingResult {
        ProcessingResult(sourceURL: job.sourceURL, outputURL: nil, originalSize: job.analysis.fileSize, optimizedSize: job.analysis.fileSize,
                         originalPixelSize: job.analysis.pixelSize, outputPixelSize: job.analysis.pixelSize,
                         inputFormat: job.analysis.format, outputFormat: job.analysis.format.closestOutputFormat,
                         decisions: [], warnings: [], status: .skipped(reason: "Cancelled"), duration: 0)
    }
}
