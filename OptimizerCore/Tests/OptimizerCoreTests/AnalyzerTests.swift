import Testing
import Foundation
import UniformTypeIdentifiers
import ImageIO
@testable import OptimizerCore

@Suite("Image analysis")
struct AnalyzerTests {
    let dir = TestImages.temporaryDirectory()

    @Test func classifiesPhotoAndGraphic() throws {
        let photo = TestImages.write(TestImages.photo(), type: .png, to: dir.appendingPathComponent("photo.png"))
        let graphic = TestImages.write(TestImages.graphic(colors: 6), type: .png, to: dir.appendingPathComponent("graphic.png"))
        let a = try TestImages.analysis(photo)
        let b = try TestImages.analysis(graphic)
        #expect(a.contentKind == .photo)
        #expect(a.uniqueColorEstimate > 2000)
        #expect(b.contentKind == .graphic)
        #expect(b.uniqueColorEstimate <= 256)
        #expect(b.isPaletteCandidate)
        #expect(a.format == .png && a.pixelSize == PixelSize(width: 640, height: 480))
    }

    @Test func acceptsJFIFFilesAsJPEG() throws {
        // A .jfif file is a JPEG in the JFIF container; ImageIO identifies it by content.
        let url = TestImages.write(TestImages.photo(), type: .jpeg, to: dir.appendingPathComponent("scan.jfif"))
        let analysis = try TestImages.analysis(url)
        #expect(analysis.format == .jpeg)
        #expect(analysis.pixelSize == PixelSize(width: 640, height: 480))
        for ext in ["jfif", "jfi", "jif"] {
            #expect(ImageFormat.importableExtensions.contains(ext))
        }
        #expect(ImageFormat.importableTypes.contains { $0.preferredFilenameExtension == "jfif" || $0.tags[.filenameExtension]?.contains("jfif") == true })
    }

    @Test func detectsTransparencyOnlyWhenUsed() throws {
        let used = TestImages.write(TestImages.transparentPhoto(), type: .png, to: dir.appendingPathComponent("alpha.png"))
        let unused = TestImages.write(TestImages.graphic(alpha: false), type: .png, to: dir.appendingPathComponent("opaque.png"))
        #expect(try TestImages.analysis(used).usesTransparency)
        #expect(try TestImages.analysis(unused).usesTransparency == false)
    }

    @Test func appliesEXIFOrientationToDimensions() throws {
        let url = TestImages.writeOrientedJPEG(to: dir.appendingPathComponent("oriented.jpg"))
        let a = try TestImages.analysis(url)
        #expect(a.orientation == 6)
        #expect(a.storedPixelSize == PixelSize(width: 400, height: 200))
        #expect(a.pixelSize == PixelSize(width: 200, height: 400))
        #expect(a.hasGPS && a.hasEXIF)
        #expect(a.format == .jpeg)
    }

    @Test func detectsAnimation() throws {
        let url = TestImages.writeAnimatedGIF(frames: 4, to: dir.appendingPathComponent("anim.gif"))
        let a = try TestImages.analysis(url)
        #expect(a.isAnimated && a.frameCount == 4 && a.format == .gif)
    }

    @Test func detectsWideGamut() throws {
        let a = try TestImages.analysis(TestImages.writeP3PNG(to: dir.appendingPathComponent("p3.png")))
        #expect(!a.isSRGB)
        #expect(a.colorSpaceName?.contains("P3") == true)
    }

    @Test func corruptedFilesThrow() {
        let url = TestImages.writeCorrupted(to: dir.appendingPathComponent("broken.jpg"))
        #expect(throws: OptimizerError.self) { try TestImages.analysis(url) }
    }

    @Test func unsupportedFilesThrow() throws {
        let url = dir.appendingPathComponent("notes.txt")
        try "hello".data(using: .utf8)!.write(to: url)
        #expect(throws: OptimizerError.self) { try TestImages.analysis(url) }
        #expect(throws: OptimizerError.fileNotFound(dir.appendingPathComponent("missing.png"))) {
            try TestImages.analysis(dir.appendingPathComponent("missing.png"))
        }
    }

    @Test func svgIsAnalyzedByIntrinsicSize() throws {
        let a = try TestImages.analysis(TestImages.writeSVG(to: dir.appendingPathComponent("logo.svg")))
        #expect(a.format == .svg)
        #expect(a.pixelSize == PixelSize(width: 120, height: 80))
        #expect(a.contentKind == .graphic)
    }

    @Test func alreadyCompressedHeuristic() throws {
        let url = TestImages.write(TestImages.photo(width: 800, height: 600), type: .jpeg, to: dir.appendingPathComponent("tiny.jpg"),
                                   properties: [kCGImageDestinationLossyCompressionQuality: 0.15])
        #expect(try TestImages.analysis(url).isLikelyAlreadyCompressed)
        let good = TestImages.write(TestImages.photo(width: 800, height: 600), type: .jpeg, to: dir.appendingPathComponent("good.jpg"),
                                    properties: [kCGImageDestinationLossyCompressionQuality: 0.95])
        #expect(try TestImages.analysis(good).isLikelyAlreadyCompressed == false)
    }
}
