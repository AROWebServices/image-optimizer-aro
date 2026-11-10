import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import OptimizerCore

@Suite("Pipeline integration")
struct PipelineIntegrationTests {
    let dir = TestImages.temporaryDirectory()

    func context(_ configure: (inout OptimizationSettings) -> Void = { _ in }, ack: Set<ItemWarning> = []) -> PipelineContext {
        var settings = OptimizationSettings()
        settings.output = OutputSettings(destination: .customFolder, suffix: .optimized)
        configure(&settings)
        return PipelineContext(settings: settings, capabilities: .current, acknowledgedWarnings: ack, customFolderURL: dir.appendingPathComponent("out"))
    }

    func run(_ url: URL, root: URL? = nil, context: PipelineContext) throws -> ProcessingResult {
        let job = try TestImages.job(url, root: root)
        let namer = OutputNamer(settings: context.settings.resolvedForProcessing.output, customFolder: context.customFolderURL)
        return OptimizationPipeline.process(job: job, context: context, namer: namer, registry: NameRegistry(protectedSources: [url]))
    }

    @Test func photoToWebPShrinksAndLeavesOriginalUntouched() throws {
        let url = TestImages.write(TestImages.photo(width: 1600, height: 1200), type: .jpeg, to: dir.appendingPathComponent("photo.jpg"),
                                   properties: [kCGImageDestinationLossyCompressionQuality: 0.95])
        let before = TestImages.sha256(url)
        let result = try run(url, context: context { $0.format = .webp; $0.quality.quality = 75; $0.resize = ResizeSettings(mode: .fit, width: 800, height: 800) })
        #expect(result.status == .success)
        #expect(result.outputURL?.lastPathComponent == "photo-optimized.webp")
        #expect(result.outputPixelSize == PixelSize(width: 800, height: 600))
        #expect(result.optimizedSize < result.originalSize)
        #expect(result.reductionPercent > 50)
        #expect(result.decisions.contains { $0.contains("verified") })
        #expect(TestImages.sha256(url) == before)
        try OutputValidator.validate(url: result.outputURL!)
        #expect(Int64(try Data(contentsOf: result.outputURL!).count) == result.optimizedSize)
    }

    @Test func exifOrientationProducesUprightOutput() throws {
        let url = TestImages.writeOrientedJPEG(to: dir.appendingPathComponent("oriented.jpg"))
        let result = try run(url, context: context { $0.format = .jpeg; $0.metadata.policy = .removeAll })
        #expect(result.status == .success)
        #expect(result.outputPixelSize == PixelSize(width: 200, height: 400))
        let props = TestImages.properties(of: result.outputURL!)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 200)
        #expect((props[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
        #expect(result.decisions.contains { $0.contains("orientation") })
    }

    @Test func transparentPNGToWebPKeepsAlpha() throws {
        let url = TestImages.write(TestImages.transparentPhoto(), type: .png, to: dir.appendingPathComponent("alpha.png"))
        let result = try run(url, context: context { $0.format = .webp })
        #expect(result.status == .success)
        let decoded = TestImages.decode(try Data(contentsOf: result.outputURL!))
        #expect(TestImages.pixel(decoded, x: 2, y: 2).a == 0)
        #expect(result.decisions.contains("Transparency preserved."))
    }

    @Test func transparentToJPEGNeedsConfirmation() throws {
        let url = TestImages.write(TestImages.transparentPhoto(), type: .png, to: dir.appendingPathComponent("alpha2.png"))
        let skipped = try run(url, context: context { $0.format = .jpeg })
        #expect(skipped.status == .skipped(reason: ItemWarning.willLoseTransparency.title))
        #expect(skipped.warnings.contains(.willLoseTransparency))
        let done = try run(url, context: context({ $0.format = .jpeg }, ack: [.willLoseTransparency]))
        #expect(done.status == .success)
        #expect(TestImages.pixel(TestImages.decode(try Data(contentsOf: done.outputURL!)), x: 2, y: 2).a == 255)
    }

    @Test func animatedGIFToWebPKeepsAnimation() throws {
        let url = TestImages.writeAnimatedGIF(frames: 4, to: dir.appendingPathComponent("anim.gif"))
        let result = try run(url, context: context { $0.format = .webp })
        #expect(result.status == .success)
        #expect(TestImages.frameCount(result.outputURL!) == 4)
        #expect(result.decisions.contains { $0.contains("Animation kept") })
    }

    @Test func animatedGIFToJPEGWarnsBeforeFlattening() throws {
        let url = TestImages.writeAnimatedGIF(frames: 3, to: dir.appendingPathComponent("anim2.gif"))
        let skipped = try run(url, context: context { $0.format = .jpeg })
        #expect(skipped.status == .skipped(reason: ItemWarning.willFlattenAnimation.title))
        let flattened = try run(url, context: context({ $0.format = .jpeg }, ack: [.willFlattenAnimation]))
        #expect(flattened.status == .success)
        #expect(TestImages.frameCount(flattened.outputURL!) == 1)
    }

    @Test func autoModePicksFormatsPerContent() throws {
        let photo = TestImages.write(TestImages.photo(width: 3000, height: 2000), type: .jpeg, to: dir.appendingPathComponent("auto-photo.jpg"))
        let graphic = TestImages.write(TestImages.graphic(colors: 5), type: .png, to: dir.appendingPathComponent("auto-graphic.png"))
        let alpha = TestImages.write(TestImages.graphic(colors: 5, alpha: true), type: .png, to: dir.appendingPathComponent("auto-alpha.png"))
        let ctx = context { $0.auto = AutoOptimizeSettings(isEnabled: true, maxWidth: 1920, maxHeight: 1920) }
        let p = try run(photo, context: ctx), g = try run(graphic, context: ctx), a = try run(alpha, context: ctx)
        #expect(p.outputFormat == .webp && p.outputPixelSize == PixelSize(width: 1920, height: 1280))
        #expect(g.outputFormat == .png)
        let alphaData = try Data(contentsOf: a.outputURL!)
        #expect(a.outputFormat == .webp)
        #expect(TestImages.pixel(TestImages.decode(alphaData), x: 1, y: 1).a == 0)
        #expect(p.decisions.first?.contains("Photo") == true)
        #expect(g.decisions.first?.contains("colours") == true)
    }

    @Test func autoModeCanPreferAVIF() throws {
        guard EncoderCapabilities.current.canEncodeAVIF else { return }
        let photo = TestImages.write(TestImages.photo(), type: .jpeg, to: dir.appendingPathComponent("avif-photo.jpg"))
        let ctx = context { $0.auto = AutoOptimizeSettings(isEnabled: true, useBestFormatAutomatically: true, preferWebPOverAVIF: false) }
        let result = try run(photo, context: ctx)
        #expect(result.outputFormat == .avif)
        #expect(result.status == .success)
    }

    @Test func keepsOriginalWhenRecompressionWouldGrow() throws {
        let url = TestImages.write(TestImages.photo(width: 400, height: 300), type: .jpeg, to: dir.appendingPathComponent("small.jpg"),
                                   properties: [kCGImageDestinationLossyCompressionQuality: 0.3])
        let result = try run(url, context: context({ $0.format = .jpeg; $0.quality.quality = 95 }, ack: [.alreadyCompressed]))
        #expect(result.status == .keptOriginal)
        #expect(result.optimizedSize == result.originalSize)
        let written = try Data(contentsOf: result.outputURL!)
        let original = try Data(contentsOf: url)
        #expect(written == original)
    }

    @Test func onlyShrinkNeverEnlarges() throws {
        let url = TestImages.write(TestImages.photo(width: 300, height: 200), type: .png, to: dir.appendingPathComponent("tiny.png"))
        let result = try run(url, context: context { $0.format = .png; $0.resize = ResizeSettings(mode: .fit, width: 2000, height: 2000, onlyShrink: true) })
        #expect(result.outputPixelSize == PixelSize(width: 300, height: 200))
        #expect(!result.warnings.contains(.willEnlarge))
        let enlarged = try run(url, context: context { $0.format = .png; $0.resize = ResizeSettings(mode: .fit, width: 600, height: 600, onlyShrink: false) })
        #expect(enlarged.outputPixelSize == PixelSize(width: 600, height: 400))
        #expect(enlarged.warnings.contains(.willEnlarge))
    }

    @Test func svgIsRasterizedAtRequestedSize() throws {
        let url = TestImages.writeSVG(to: dir.appendingPathComponent("logo.svg"))
        let result = try run(url, context: context { $0.format = .png; $0.resize = ResizeSettings(mode: .exact, width: 600, height: nil, onlyShrink: false) })
        #expect(result.status == .success)
        #expect(result.outputPixelSize == PixelSize(width: 600, height: 400))
        #expect(result.warnings.contains(.svgRasterized))
        let decoded = TestImages.decode(try Data(contentsOf: result.outputURL!))
        let centre = TestImages.pixel(decoded, x: 300, y: 200)
        #expect(centre.r > 240 && centre.g > 240 && centre.b > 240)
    }

    @Test func corruptedFileFailsGracefully() throws {
        let url = TestImages.writeCorrupted(to: dir.appendingPathComponent("broken.jpg"))
        #expect(throws: OptimizerError.self) { try TestImages.job(url) }
    }

    @Test func folderStructureIsPreserved() throws {
        let root = dir.appendingPathComponent("site")
        let nested = root.appendingPathComponent("assets/hero")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let url = TestImages.write(TestImages.photo(width: 200, height: 100), type: .png, to: nested.appendingPathComponent("a.png"))
        let result = try run(url, root: root, context: context { $0.format = .webp; $0.output.preserveFolderStructure = true })
        #expect(result.outputURL?.path.hasSuffix("out/assets/hero/a-optimized.webp") == true)
    }

    @Test func replaceOriginalsSwapsFileAfterConfirmation() throws {
        let folder = dir.appendingPathComponent("replace")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = TestImages.write(TestImages.photo(width: 800, height: 600), type: .jpeg, to: folder.appendingPathComponent("r.jpg"),
                                   properties: [kCGImageDestinationLossyCompressionQuality: 1.0])
        let originalSize = try Data(contentsOf: url).count
        let ctx = PipelineContext(settings: {
            var s = OptimizationSettings(); s.format = .jpeg; s.quality.quality = 70
            s.output = OutputSettings(destination: .replaceOriginals); return s
        }(), acknowledgedWarnings: [.replaceOriginal])
        let result = try run(url, context: ctx)
        #expect(result.status == .success)
        #expect(result.outputURL == url)
        #expect(try Data(contentsOf: url).count < originalSize)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func preflightAggregatesConfirmations() throws {
        let gif = TestImages.writeAnimatedGIF(to: dir.appendingPathComponent("pf.gif"))
        let alpha = TestImages.write(TestImages.transparentPhoto(), type: .png, to: dir.appendingPathComponent("pf.png"))
        let items = [BatchItem(id: UUID(), job: try TestImages.job(gif)), BatchItem(id: UUID(), job: try TestImages.job(alpha))]
        let report = PreflightReport.make(items: items, context: context { $0.format = .jpeg })
        #expect(report.confirmations[.willFlattenAnimation] == 1)
        #expect(report.confirmations[.willLoseTransparency] == 1)
        #expect(report.destinationFolders.count == 1)
    }

    @Test func externalSamplesIfProvided() throws {
        guard let folder = TestImages.externalSamples else { return }
        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { ImageFormat.importableExtensions.contains($0.pathExtension.lowercased()) }
        for url in urls {
            let result = try run(url, root: folder, context: context { $0.auto.isEnabled = true })
            #expect(result.status.isSuccess, "\(url.lastPathComponent): \(result.status)")
        }
    }
}
