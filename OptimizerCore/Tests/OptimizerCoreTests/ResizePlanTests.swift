import Testing
import Foundation
@testable import OptimizerCore

@Suite("Resize geometry")
struct ResizePlanTests {
    let landscape = PixelSize(width: 4000, height: 3000)
    let portrait = PixelSize(width: 3000, height: 4000)

    @Test func fitKeepsAspectRatioAndBoundsLongestSide() {
        let plan = Resizer.plan(source: landscape, settings: ResizeSettings(mode: .fit, width: 1920, height: 1920))
        #expect(plan.outputSize == PixelSize(width: 1920, height: 1440))
        let portraitPlan = Resizer.plan(source: portrait, settings: ResizeSettings(mode: .fit, width: 1920, height: 1920))
        #expect(portraitPlan.outputSize == PixelSize(width: 1440, height: 1920))
    }

    @Test func fitWithOnlyWidth() {
        let plan = Resizer.plan(source: landscape, settings: ResizeSettings(mode: .fit, width: 800, height: nil))
        #expect(plan.outputSize == PixelSize(width: 800, height: 600))
        #expect(!plan.isEnlarging)
    }

    @Test func onlyShrinkPreventsEnlarging() {
        let small = PixelSize(width: 640, height: 480)
        let plan = Resizer.plan(source: small, settings: ResizeSettings(mode: .fit, width: 1920, height: 1920, onlyShrink: true))
        #expect(plan.isNoOp)
        #expect(plan.outputSize == small)
        #expect(plan.note != nil)
    }

    @Test func enlargingIsFlaggedWhenAllowed() {
        let small = PixelSize(width: 640, height: 480)
        let plan = Resizer.plan(source: small, settings: ResizeSettings(mode: .fit, width: 1280, height: 1280, onlyShrink: false))
        #expect(plan.isEnlarging)
        #expect(plan.outputSize == PixelSize(width: 1280, height: 960))
    }

    @Test func fillCropsToTargetAspect() {
        let plan = Resizer.plan(source: landscape, settings: ResizeSettings(mode: .fill, width: 1000, height: 1000))
        #expect(plan.outputSize == PixelSize(width: 1000, height: 1000))
        #expect(abs(plan.drawRect.width - 1333.33) < 1)
        #expect(plan.drawRect.minX < 0)
    }

    @Test func fillWithoutEnlargingCropsAtNativeScale() {
        let small = PixelSize(width: 600, height: 400)
        let plan = Resizer.plan(source: small, settings: ResizeSettings(mode: .fill, width: 1000, height: 1000, onlyShrink: true))
        #expect(plan.outputSize == PixelSize(width: 400, height: 400))
        #expect(!plan.isEnlarging)
    }

    @Test func exactWithLockDerivesHeight() {
        let plan = Resizer.plan(source: landscape, settings: ResizeSettings(mode: .exact, width: 1000, height: nil, lockAspectRatio: true))
        #expect(plan.outputSize == PixelSize(width: 1000, height: 750))
    }

    @Test func exactWithoutLockStretches() {
        let plan = Resizer.plan(source: landscape, settings: ResizeSettings(mode: .exact, width: 500, height: 500, lockAspectRatio: false))
        #expect(plan.outputSize == PixelSize(width: 500, height: 500))
        #expect(plan.drawRect == CGRect(x: 0, y: 0, width: 500, height: 500))
    }

    @Test func percentageScaling() {
        let plan = Resizer.plan(source: landscape, settings: ResizeSettings(mode: .percentage, percentage: 50))
        #expect(plan.outputSize == PixelSize(width: 2000, height: 1500))
        let noEnlarge = Resizer.plan(source: landscape, settings: ResizeSettings(mode: .percentage, percentage: 200, onlyShrink: true))
        #expect(noEnlarge.isNoOp)
    }

    @Test func presetsRoundTrip() {
        for edge in ResizeSettings.longestEdgePresets {
            #expect(ResizeSettings.preset(longestEdge: edge).matchingLongestEdgePreset == edge)
        }
    }

    @Test func validationMessages() {
        #expect(ResizeSettings(mode: .fill, width: 100, height: nil).validationMessage != nil)
        #expect(ResizeSettings(mode: .fit, width: nil, height: nil).validationMessage != nil)
        #expect(ResizeSettings(mode: .fit, width: 100, height: nil).validationMessage == nil)
        #expect(ResizeSettings(mode: .percentage, percentage: 0).validationMessage != nil)
    }

    @Test func renderProducesRequestedSizeAndKeepsAlpha() throws {
        let image = TestImages.transparentPhoto(width: 300, height: 200)
        let plan = Resizer.plan(source: PixelSize(width: 300, height: 200), settings: ResizeSettings(mode: .fit, width: 150, height: 150))
        let rendered = try Resizer.render(image, plan: plan, options: .init(keepAlpha: true, colorSpace: TestImages.sRGB))
        #expect(rendered.width == 150 && rendered.height == 100)
        #expect(TestImages.pixel(rendered, x: 1, y: 1).a == 0)
        let flattened = try Resizer.render(image, plan: plan, options: .init(keepAlpha: false, colorSpace: TestImages.sRGB))
        let corner = TestImages.pixel(flattened, x: 1, y: 1)
        #expect(corner.a == 255 && corner.r == 255 && corner.g == 255)
    }
}
