import Testing
import Foundation
import UniformTypeIdentifiers
@testable import OptimizerCore

@Suite("Batch processing")
struct BatchTests {
    let dir = TestImages.temporaryDirectory()

    func makeItems(count: Int, size: Int = 600) throws -> [BatchItem] {
        try (0..<count).map { i in
            let url = TestImages.write(TestImages.photo(width: size, height: size * 3 / 4, seed: UInt64(i + 1)), type: .png, to: dir.appendingPathComponent("b\(i).png"))
            return BatchItem(id: UUID(), job: try TestImages.job(url))
        }
    }

    func context() -> PipelineContext {
        var settings = OptimizationSettings()
        settings.format = .webp
        settings.output = OutputSettings(destination: .customFolder)
        return PipelineContext(settings: settings, customFolderURL: dir.appendingPathComponent("out"))
    }

    @Test func processesEveryItemAndSummarises() async throws {
        let items = try makeItems(count: 6)
        let processor = BatchProcessor(maxConcurrency: 3)
        var finished = 0
        var started = Set<UUID>()
        var summary: BatchSummary?
        var lastProgress = (0, 0)
        for await event in processor.run(items: items, context: context()) {
            switch event {
            case .itemStarted(let id): started.insert(id)
            case .itemFinished(_, let result): finished += 1; #expect(result.status == .success)
            case .progress(let done, let total): lastProgress = (done, total)
            case .finished(let s): summary = s
            }
        }
        #expect(finished == 6 && started.count == 6)
        #expect(lastProgress == (6, 6))
        let s = try #require(summary)
        #expect(s.processed == 6 && s.succeeded == 6 && s.failed == 0)
        #expect(s.totalOptimizedSize < s.totalOriginalSize)
        #expect(s.averageReductionPercent > 0)
        #expect(!s.wasCancelled)
    }

    @Test func cancellationStopsEarly() async throws {
        let items = try makeItems(count: 12, size: 1800)
        let processor = BatchProcessor(maxConcurrency: 1)
        var finished = 0
        var summary: BatchSummary?
        for await event in processor.run(items: items, context: context()) {
            switch event {
            case .itemFinished:
                finished += 1
                if finished == 2 { processor.cancel() }
            case .finished(let s): summary = s
            default: break
            }
        }
        let s = try #require(summary)
        #expect(s.wasCancelled)
        #expect(s.succeeded < 12)
    }

    @Test func pauseHoldsNewItems() async throws {
        let items = try makeItems(count: 3)
        let processor = BatchProcessor(maxConcurrency: 1)
        processor.pause()
        let start = Date()
        var firstFinish: Date?
        var finished = 0
        Task.detached {
            try? await Task.sleep(for: .milliseconds(600))
            processor.resume()
        }
        for await event in processor.run(items: items, context: context()) {
            if case .itemFinished = event {
                finished += 1
                if firstFinish == nil { firstFinish = Date() }
            }
        }
        #expect(finished == 3)
        let gap = try #require(firstFinish).timeIntervalSince(start)
        #expect(gap >= 0.5)
    }

    @Test func failuresAreCountedNotFatal() async throws {
        var items = try makeItems(count: 2)
        // A file that analyses fine but vanishes before processing.
        let ghost = TestImages.write(TestImages.photo(width: 100, height: 100), type: .png, to: dir.appendingPathComponent("ghost.png"))
        items.append(BatchItem(id: UUID(), job: try TestImages.job(ghost)))
        try FileManager.default.removeItem(at: ghost)
        var summary: BatchSummary?
        var results: [ProcessingResult] = []
        for await event in BatchProcessor(maxConcurrency: 2).run(items: items, context: context()) {
            if case .itemFinished(_, let r) = event { results.append(r) }
            if case .finished(let s) = event { summary = s }
        }
        let s = try #require(summary)
        #expect(s.failed == 1 && s.succeeded == 2)
        let failure = results.first { if case .failed = $0.status { return true } else { return false } }
        if case .failed(let message)? = failure?.status { #expect(!message.isEmpty) } else { Issue.record("no failure recorded") }
    }

    @Test func sameNamesFromDifferentFoldersDoNotCollide() async throws {
        let a = dir.appendingPathComponent("A"), b = dir.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let items = [
            BatchItem(id: UUID(), job: try TestImages.job(TestImages.write(TestImages.photo(width: 200, height: 100), type: .png, to: a.appendingPathComponent("same.png")))),
            BatchItem(id: UUID(), job: try TestImages.job(TestImages.write(TestImages.photo(width: 200, height: 100, seed: 5), type: .jpeg, to: b.appendingPathComponent("same.jpg"))))
        ]
        var ctx = context()
        ctx.settings.output.preserveFolderStructure = false
        var outputs: [URL] = []
        for await event in BatchProcessor(maxConcurrency: 2).run(items: items, context: ctx) {
            if case .itemFinished(_, let r) = event, let url = r.outputURL { outputs.append(url) }
        }
        #expect(outputs.count == 2)
        #expect(Set(outputs.map(\.path)).count == 2)
    }
}
