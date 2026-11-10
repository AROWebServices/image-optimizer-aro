import Foundation
import CoreGraphics
import CoreImage

/// The geometry of one resize: computed up front so the UI can show it before processing.
public struct ResizePlan: Hashable, Sendable {
    public var sourceSize: PixelSize
    public var outputSize: PixelSize
    /// Where the scaled source lands inside the output canvas (differs from the canvas for fill/crop).
    public var drawRect: CGRect
    public var isEnlarging: Bool
    public var isNoOp: Bool
    public var note: String?

    public var scale: Double { sourceSize.width == 0 ? 1 : drawRect.width / Double(sourceSize.width) }
}

public enum Resizer {
    /// Pure geometry. `source` must already be orientation-corrected.
    public static func plan(source: PixelSize, settings: ResizeSettings) -> ResizePlan {
        let width = Double(max(1, source.width))
        let height = Double(max(1, source.height))
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let unchanged = ResizePlan(sourceSize: source, outputSize: source, drawRect: full, isEnlarging: false, isNoOp: true, note: nil)

        func clampedOutput(_ w: Double, _ h: Double) -> PixelSize {
            PixelSize(width: max(1, Int(w.rounded())), height: max(1, Int(h.rounded())))
        }

        switch settings.mode {
        case .none:
            return unchanged

        case .percentage:
            var factor = settings.percentage / 100
            guard factor > 0 else { return unchanged }
            var note: String?
            if factor > 1 && settings.onlyShrink {
                factor = 1
                note = "Not enlarged: “Only shrink images” is on."
            }
            if factor == 1 { return ResizePlan(sourceSize: source, outputSize: source, drawRect: full, isEnlarging: false, isNoOp: true, note: note) }
            let out = clampedOutput(width * factor, height * factor)
            return ResizePlan(sourceSize: source, outputSize: out,
                              drawRect: CGRect(x: 0, y: 0, width: out.width, height: out.height),
                              isEnlarging: factor > 1, isNoOp: false, note: note)

        case .fit:
            let maxW = settings.width.map(Double.init) ?? .infinity
            let maxH = settings.height.map(Double.init) ?? .infinity
            guard maxW.isFinite || maxH.isFinite else { return unchanged }
            var factor = min(maxW / width, maxH / height)
            var note: String?
            if factor > 1 && settings.onlyShrink {
                factor = 1
                note = "Already smaller than the limit; not enlarged."
            }
            if abs(factor - 1) < 0.0001 {
                return ResizePlan(sourceSize: source, outputSize: source, drawRect: full, isEnlarging: false, isNoOp: true, note: note)
            }
            // Keep the constraining side exact and derive the other one from the aspect ratio.
            let out: PixelSize
            if maxW / width <= maxH / height {
                let w = maxW.isFinite ? maxW : (width * factor).rounded()
                out = clampedOutput(w, w * height / width)
            } else {
                let h = maxH.isFinite ? maxH : (height * factor).rounded()
                out = clampedOutput(h * width / height, h)
            }
            return ResizePlan(sourceSize: source, outputSize: out,
                              drawRect: CGRect(x: 0, y: 0, width: out.width, height: out.height),
                              isEnlarging: factor > 1, isNoOp: false, note: note)

        case .fill:
            guard let targetW = settings.width, let targetH = settings.height, targetW > 0, targetH > 0 else { return unchanged }
            var tw = Double(targetW), th = Double(targetH)
            var note: String?
            var factor = max(tw / width, th / height)
            if factor > 1 && settings.onlyShrink {
                // Crop to the requested aspect ratio at native resolution instead of enlarging.
                let aspect = tw / th
                if width / height > aspect {
                    th = height
                    tw = (height * aspect).rounded()
                } else {
                    tw = width
                    th = (width / aspect).rounded()
                }
                factor = max(tw / width, th / height)
                note = "Cropped to the requested aspect ratio without enlarging."
            }
            let scaledW = width * factor, scaledH = height * factor
            let out = clampedOutput(tw, th)
            let drawRect = CGRect(x: (Double(out.width) - scaledW) / 2, y: (Double(out.height) - scaledH) / 2, width: scaledW, height: scaledH)
            let noOp = out == source && factor == 1
            return ResizePlan(sourceSize: source, outputSize: out, drawRect: drawRect, isEnlarging: factor > 1, isNoOp: noOp, note: note)

        case .exact:
            var tw = settings.width.map(Double.init)
            var th = settings.height.map(Double.init)
            if settings.lockAspectRatio || tw == nil || th == nil {
                if let w = tw { th = (w * height / width).rounded() }
                else if let h = th { tw = (h * width / height).rounded() }
            }
            guard var finalW = tw, var finalH = th, finalW > 0, finalH > 0 else { return unchanged }
            var note: String?
            var enlarging = finalW > width || finalH > height
            if enlarging && settings.onlyShrink {
                let factor = min(width / finalW, height / finalH, 1)
                finalW = (finalW * factor).rounded()
                finalH = (finalH * factor).rounded()
                enlarging = false
                note = "Reduced to fit inside the original because “Only shrink images” is on."
            }
            let out = clampedOutput(finalW, finalH)
            let noOp = out == source
            return ResizePlan(sourceSize: source, outputSize: out,
                              drawRect: CGRect(x: 0, y: 0, width: out.width, height: out.height),
                              isEnlarging: enlarging, isNoOp: noOp, note: note)
        }
    }

    public struct RenderOptions: Sendable {
        public var keepAlpha: Bool
        public var grayscale: Bool
        public var colorSpace: CGColorSpace
        public var sharpen: Bool
        /// Background used when alpha is dropped.
        public var matteWhite: Bool

        public init(keepAlpha: Bool, grayscale: Bool = false, colorSpace: CGColorSpace, sharpen: Bool = false, matteWhite: Bool = true) {
            self.keepAlpha = keepAlpha
            self.grayscale = grayscale
            self.colorSpace = colorSpace
            self.sharpen = sharpen
            self.matteWhite = matteWhite
        }
    }

    /// Draws `image` into a fresh bitmap according to `plan`, converting colour space and alpha as requested.
    /// Core Graphics' high interpolation is a proper multi-tap filter and gives clean downsampling.
    public static func render(_ image: CGImage, plan: ResizePlan, options: RenderOptions) throws -> CGImage {
        let width = plan.outputSize.width
        let height = plan.outputSize.height
        let bitmapInfo: UInt32
        let space: CGColorSpace
        if options.grayscale && !options.keepAlpha {
            space = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!
            bitmapInfo = CGImageAlphaInfo.none.rawValue
        } else {
            space = options.colorSpace
            bitmapInfo = options.keepAlpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        }
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: bitmapInfo) else {
            throw OptimizerError.encodingFailed(.png, "Could not allocate a \(width)×\(height) bitmap.")
        }
        context.interpolationQuality = .high
        if !options.keepAlpha {
            context.setFillColor(options.matteWhite ? CGColor.white : CGColor.black)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.draw(image, in: plan.drawRect)
        guard var result = context.makeImage() else {
            throw OptimizerError.encodingFailed(.png, "Rendering produced no image.")
        }
        if options.sharpen && !plan.isNoOp {
            result = sharpen(result) ?? result
        }
        return result
    }

    /// Gentle unsharp mask that restores edge contrast lost in downsampling. Optional and opt-in.
    static func sharpen(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIUnsharpMask") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(0.8, forKey: kCIInputRadiusKey)
        filter.setValue(0.35, forKey: kCIInputIntensityKey)
        guard let output = filter.outputImage else { return nil }
        let context = CIContext(options: [.workingColorSpace: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!])
        return context.createCGImage(output, from: input.extent, format: .RGBA8, colorSpace: image.colorSpace)
    }
}
