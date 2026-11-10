import Testing
import Foundation
@testable import OptimizerCore

@Suite("Format selection rules")
struct FormatSelectorTests {
    func analysis(format: ImageFormat = .jpeg, kind: ContentKind = .photo, transparency: Bool = false,
                  animated: Bool = false, colors: Int = 50_000) -> ImageAnalysis {
        ImageAnalysis(url: URL(fileURLWithPath: "/tmp/x.\(format.rawValue)"), fileSize: 100_000, format: format,
                      utTypeIdentifier: "x", pixelSize: PixelSize(width: 800, height: 600), storedPixelSize: PixelSize(width: 800, height: 600),
                      orientation: 1, bitDepth: 8, hasAlphaChannel: transparency, usesTransparency: transparency,
                      isAnimated: animated, frameCount: animated ? 5 : 1, colorSpaceName: "sRGB", isSRGB: true,
                      hasEXIF: false, hasGPS: false, contentKind: kind, uniqueColorEstimate: colors, bitsPerPixel: 1.7)
    }

    func decide(_ a: ImageAnalysis, allowAVIF: Bool = false, compatibility: Bool = false,
                capabilities: EncoderCapabilities = .all) -> FormatSelector.Decision {
        FormatSelector.decide(.init(analysis: a, capabilities: capabilities, allowAVIF: allowAVIF, compatibilityMode: compatibility))
    }

    @Test func photoPrefersWebPByDefault() {
        let d = decide(analysis())
        #expect(d.format == .webp)
        #expect(d.lossless == false)
    }

    @Test func photoUsesAVIFWhenAllowed() {
        #expect(decide(analysis(), allowAVIF: true).format == .avif)
    }

    @Test func avifFallsBackWhenEncoderMissing() {
        let caps = EncoderCapabilities(canEncodeAVIF: false, canEncodeHEIC: true, canDecodeWebP: true, canDecodeAVIF: true, webpVersion: "t")
        #expect(decide(analysis(), allowAVIF: true, capabilities: caps).format == .webp)
    }

    @Test func compatibilityModeUsesJPEGForPhotos() {
        #expect(decide(analysis(), compatibility: true).format == .jpeg)
    }

    @Test func transparentGraphicUsesLosslessWebP() {
        let d = decide(analysis(format: .png, kind: .graphic, transparency: true, colors: 900))
        #expect(d.format == .webp)
        #expect(d.lossless)
    }

    @Test func transparentGraphicUsesPNGInCompatibilityMode() {
        let d = decide(analysis(format: .png, kind: .graphic, transparency: true), compatibility: true)
        #expect(d.format == .png)
    }

    @Test func fewColoursBecomeIndexedPNG() {
        let d = decide(analysis(format: .png, kind: .graphic, colors: 12))
        #expect(d.format == .png)
        #expect(d.reason.contains("12 colours"))
    }

    @Test func screenshotWithManyColoursUsesLosslessWebP() {
        let d = decide(analysis(format: .png, kind: .graphic, colors: 5000))
        #expect(d.format == .webp)
        #expect(d.lossless)
    }

    @Test func transparentPhotoKeepsAlpha() {
        let d = decide(analysis(format: .png, kind: .photo, transparency: true))
        #expect(d.format == .webp)
        #expect(d.format.supportsTransparency)
        #expect(decide(analysis(format: .png, kind: .photo, transparency: true), compatibility: true).format == .png)
    }

    @Test func animatedGIFBecomesAnimatedWebP() {
        let d = decide(analysis(format: .gif, kind: .graphic, animated: true))
        #expect(d.format == .webp)
        #expect(d.format.supportsAnimation)
    }

    @Test func animatedGIFStaysGIFInCompatibilityMode() {
        #expect(decide(analysis(format: .gif, kind: .graphic, animated: true), compatibility: true).format == .gif)
    }

    @Test func svgRasterizesLosslessly() {
        let d = decide(analysis(format: .svg, kind: .graphic))
        #expect(d.lossless)
        #expect(d.format == .webp)
    }

    @Test func rulesAreOrderedAnimationFirst() {
        #expect(FormatSelector.rules.first?.name.contains("Animated") == true)
        #expect(FormatSelector.rules.last?.name == "Photos")
    }
}
