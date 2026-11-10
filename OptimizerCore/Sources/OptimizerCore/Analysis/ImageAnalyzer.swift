import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

/// Reads a file's properties and a small sample of its pixels without decoding the full image.
public struct ImageAnalyzer: Sendable {
    public var sampleSize: Int

    public init(sampleSize: Int = 256) {
        self.sampleSize = sampleSize
    }

    public func analyze(url: URL) throws -> ImageAnalysis {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { throw OptimizerError.fileNotFound(url) }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let fileSize = Int64(values?.fileSize ?? 0)
        let declaredType = values?.contentType

        if declaredType?.conforms(to: .svg) == true || url.pathExtension.lowercased() == "svg" {
            return try analyzeSVG(url: url, fileSize: fileSize)
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw OptimizerError.unreadable(url)
        }
        guard let typeIdentifier = CGImageSourceGetType(source) as String? else {
            throw OptimizerError.unsupportedFormat(url, declaredType?.localizedDescription ?? url.pathExtension)
        }
        let format = ImageFormat(utTypeIdentifier: typeIdentifier)
        if format == .other {
            throw OptimizerError.unsupportedFormat(url, typeIdentifier)
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let storedWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let storedHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              storedWidth > 0, storedHeight > 0 else {
            throw OptimizerError.corrupted(url)
        }

        let orientation = ImageAnalyzer.orientation(from: properties)
        let stored = PixelSize(width: storedWidth, height: storedHeight)
        let oriented = orientation >= 5 ? PixelSize(width: storedHeight, height: storedWidth) : stored

        let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false
        let depth = properties[kCGImagePropertyDepth] as? Int ?? 8
        let profileName = properties[kCGImagePropertyProfileName] as? String
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        let hasEXIF = !(exif?.isEmpty ?? true) || !(tiff?.isEmpty ?? true) || !(iptc?.isEmpty ?? true)
        let hasGPS = !(gps?.isEmpty ?? true)
        let isAnimated = frameCount > 1 && format.supportsAnimation

        // A small, orientation-corrected sample. Decoding must succeed or the file is unusable.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: sampleSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let sampleImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw OptimizerError.corrupted(url)
        }
        let sample = ContentClassifier.classify(sampleImage, hintLossyPhotoFormat: format.isLossy)
        let colorSpaceName = profileName ?? (sampleImage.colorSpace?.name as String?)
        let isSRGB = ImageAnalyzer.isSRGBName(colorSpaceName) || sampleImage.colorSpace?.name == CGColorSpace.sRGB

        let bitsPerPixel = oriented.pixelCount > 0 ? Double(fileSize * 8) / Double(oriented.pixelCount) : 0

        return ImageAnalysis(url: url, fileSize: fileSize, format: format, utTypeIdentifier: typeIdentifier,
                             pixelSize: oriented, storedPixelSize: stored, orientation: orientation, bitDepth: depth,
                             hasAlphaChannel: hasAlpha, usesTransparency: hasAlpha && sample.usesTransparency,
                             isAnimated: isAnimated, frameCount: frameCount,
                             colorSpaceName: colorSpaceName, isSRGB: isSRGB, hasEXIF: hasEXIF, hasGPS: hasGPS,
                             contentKind: sample.contentKind, uniqueColorEstimate: sample.uniqueColors,
                             bitsPerPixel: bitsPerPixel)
    }

    private func analyzeSVG(url: URL, fileSize: Int64) throws -> ImageAnalysis {
        guard let size = SVGRasterizer.intrinsicSize(of: url) else { throw OptimizerError.corrupted(url) }
        return ImageAnalysis(url: url, fileSize: fileSize, format: .svg, utTypeIdentifier: UTType.svg.identifier,
                             pixelSize: size, storedPixelSize: size, orientation: 1, bitDepth: 8,
                             hasAlphaChannel: true, usesTransparency: true, isAnimated: false, frameCount: 1,
                             colorSpaceName: "sRGB", isSRGB: true, hasEXIF: false, hasGPS: false,
                             contentKind: .graphic, uniqueColorEstimate: 0, bitsPerPixel: 0)
    }

    static func orientation(from properties: [CFString: Any]) -> Int {
        if let value = properties[kCGImagePropertyOrientation] as? Int, (1...8).contains(value) { return value }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let value = tiff[kCGImagePropertyTIFFOrientation] as? Int, (1...8).contains(value) { return value }
        return 1
    }

    static func isSRGBName(_ name: String?) -> Bool {
        guard let name = name?.lowercased() else { return false }
        return name.contains("srgb") || name.contains("iec61966")
    }
}
