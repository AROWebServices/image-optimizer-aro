import Testing
import Foundation
import ImageIO
@testable import OptimizerCore

@Suite("Metadata and colour handling")
struct MetadataAndColorTests {
    let dir = TestImages.temporaryDirectory()

    func encodeOriented(policy: MetadataPolicy, stripGPS: Bool = true, format: FormatSelection = .jpeg) throws -> Data {
        let url = TestImages.writeOrientedJPEG(to: dir.appendingPathComponent("\(policy.rawValue)-\(stripGPS)-\(format.rawValue).jpg"))
        var settings = OptimizationSettings()
        settings.format = format
        settings.metadata = MetadataSettings(policy: policy, convertToSRGB: true, stripGPS: stripGPS)
        let context = PipelineContext(settings: settings, capabilities: .current)
        let job = try TestImages.job(url)
        let plan = OptimizationPipeline.plan(for: job, context: context)
        return try OptimizationPipeline.encode(job: job, plan: plan, context: context).data
    }

    @Test func removeAllStripsEverything() throws {
        let props = TestImages.properties(of: try encodeOriented(policy: .removeAll))
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFArtist] == nil)
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifLensModel] == nil)
    }

    @Test func colorProfileOnlyStripsTags() throws {
        let props = TestImages.properties(of: try encodeOriented(policy: .colorProfileOnly))
        #expect((props[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFArtist] == nil)
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test func keepAllKeepsTagsButDropsGPSAndNormalisesOrientation() throws {
        let props = TestImages.properties(of: try encodeOriented(policy: .keepAll))
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFArtist] as? String == "Test Artist")
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifLensModel] as? String == "Test Lens 50mm")
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        let orientation = (props[kCGImagePropertyOrientation] as? Int) ?? (tiff?[kCGImagePropertyTIFFOrientation] as? Int) ?? 1
        #expect(orientation == 1)
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 200)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 400)
    }

    @Test func keepAllCanRetainGPSWhenAsked() throws {
        let props = TestImages.properties(of: try encodeOriented(policy: .keepAll, stripGPS: false))
        #expect(props[kCGImagePropertyGPSDictionary] != nil)
    }

    @Test func copyrightOnlyKeepsArtistButNotCamera() throws {
        let props = TestImages.properties(of: try encodeOriented(policy: .copyrightOnly))
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        #expect(tiff?[kCGImagePropertyTIFFArtist] as? String == "Test Artist")
        #expect(tiff?[kCGImagePropertyTIFFCopyright] as? String == "© Test Artist")
        #expect(tiff?[kCGImagePropertyTIFFMake] == nil)
        #expect(props[kCGImagePropertyGPSDictionary] == nil)
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        #expect(exif?[kCGImagePropertyExifLensModel] == nil)
    }

    @Test func webpKeepsXMPForCopyright() throws {
        // ImageIO does not expose WebP XMP on read, so inspect the container: an "XMP " chunk holding the artist.
        let data = try encodeOriented(policy: .copyrightOnly, format: .webp)
        #expect(data.range(of: Data("XMP ".utf8)) != nil)
        #expect(data.range(of: Data("Test Artist".utf8)) != nil)
        let stripped = try encodeOriented(policy: .removeAll, format: .webp)
        #expect(stripped.range(of: Data("XMP ".utf8)) == nil)
        #expect(stripped.count < data.count)
    }

    @Test func wideGamutIsConvertedToSRGBByDefault() throws {
        let url = TestImages.writeP3PNG(to: dir.appendingPathComponent("p3.png"))
        var settings = OptimizationSettings()
        settings.format = .png
        settings.metadata = MetadataSettings(policy: .colorProfileOnly, convertToSRGB: true)
        let context = PipelineContext(settings: settings)
        let job = try TestImages.job(url)
        let plan = OptimizationPipeline.plan(for: job, context: context)
        #expect(plan.convertToSRGB)
        #expect(plan.decisions.contains { $0.contains("sRGB") })
        let data = try OptimizationPipeline.encode(job: job, plan: plan, context: context).data
        let decoded = TestImages.decode(data)
        #expect(decoded.colorSpace?.name == CGColorSpace.sRGB)
        // Colour management keeps the appearance: a mid-grey stays close to mid-grey.
        let original = TestImages.decode(try Data(contentsOf: url))
        let a = TestImages.pixel(original, x: 100, y: 75), b = TestImages.pixel(decoded, x: 100, y: 75)
        #expect(abs(a.r - b.r) < 24 && abs(a.g - b.g) < 24 && abs(a.b - b.b) < 24)
    }

    @Test func profileIsKeptWhenConversionIsOff() throws {
        let url = TestImages.writeP3PNG(to: dir.appendingPathComponent("p3keep.png"))
        for format in [FormatSelection.png, .webp, .jpeg] {
            var settings = OptimizationSettings()
            settings.format = format
            settings.metadata = MetadataSettings(policy: .colorProfileOnly, convertToSRGB: false)
            let context = PipelineContext(settings: settings)
            let job = try TestImages.job(url)
            let plan = OptimizationPipeline.plan(for: job, context: context)
            #expect(!plan.convertToSRGB)
            let data = try OptimizationPipeline.encode(job: job, plan: plan, context: context).data
            let decoded = TestImages.decode(data)
            #expect(decoded.colorSpace?.name != CGColorSpace.sRGB, "\(format)")
        }
    }

    @Test func removeAllForcesSRGB() {
        let settings = MetadataSettings(policy: .removeAll, convertToSRGB: false)
        #expect(settings.effectiveConvertToSRGB)
    }
}
