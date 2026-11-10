// End-to-end verification of the optimization pipeline without the UI.
//
//   Scripts/verify-batch.sh [output-folder]
//
// Generates a realistic sample set (photos, transparent PNGs, a 6000×4000 image, EXIF-rotated
// JPEGs with GPS, an animated GIF, a Display P3 image and an SVG), runs them through the same
// BatchProcessor the app uses, then checks that every output opens, that dimensions and
// transparency are right, and that no source file changed.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import OptimizerCore

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

struct LCG { var state: UInt64; mutating func next() -> UInt8 { state = state &* 6364136223846793005 &+ 1442695040888963407; return UInt8(truncatingIfNeeded: state >> 33) } }

func context(_ w: Int, _ h: Int, alpha: Bool, space: CGColorSpace = sRGB) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
}

func photo(_ w: Int, _ h: Int, seed: UInt64, space: CGColorSpace = sRGB) -> CGImage {
    let ctx = context(w, h, alpha: false, space: space)
    var rng = LCG(state: seed)
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<h {
        for x in 0..<w {
            let i = y * ctx.bytesPerRow + x * 4
            let n = Int(rng.next() % 28)
            let cx = Double(x - w / 2) / Double(w), cy = Double(y - h / 2) / Double(h)
            let vignette = max(0, 1 - (cx * cx + cy * cy) * 1.6)
            data[i] = UInt8(min(255, Int(Double(x * 255 / max(1, w)) * vignette) + n))
            data[i + 1] = UInt8(min(255, Int(Double(y * 255 / max(1, h)) * vignette) + n))
            data[i + 2] = UInt8(min(255, Int(120 * vignette) + n))
            data[i + 3] = 255
        }
    }
    // A few sharp shapes so blockiness would be visible.
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    for k in 0..<12 { ctx.fill(CGRect(x: w / 12 * k, y: h / 3, width: w / 40, height: h / 6)) }
    return ctx.makeImage()!
}

func graphic(_ w: Int, _ h: Int, colors: Int, alpha: Bool) -> CGImage {
    let ctx = context(w, h, alpha: alpha)
    if alpha { ctx.clear(CGRect(x: 0, y: 0, width: w, height: h)) } else { ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h)) }
    for i in 0..<colors {
        ctx.setFillColor(CGColor(red: CGFloat((i * 53) % 255) / 255, green: CGFloat((i * 97) % 255) / 255, blue: CGFloat((i * 193) % 255) / 255, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: (w / colors) * i, y: h / 4, width: w / colors, height: h / 2))
    }
    return ctx.makeImage()!
}

func write(_ image: CGImage, _ type: UTType, _ url: URL, _ props: [CFString: Any] = [:]) {
    let d = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(d, image, props as CFDictionary)
    precondition(CGImageDestinationFinalize(d))
}

func fingerprint(_ url: URL) -> Int {
    var hasher = Hasher()
    hasher.combine(try! Data(contentsOf: url))
    return hasher.finalize()
}

// MARK: - Sample set

let arguments = CommandLine.arguments.dropFirst()
let base = arguments.first.map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory.appendingPathComponent("ImageOptimizer-verify-\(Int(Date().timeIntervalSince1970))")
let input = base.appendingPathComponent("input/photos/trip", isDirectory: true)
let output = base.appendingPathComponent("output", isDirectory: true)
try! FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

print("Generating samples in \(input.path)…")
write(photo(3000, 2000, seed: 1), .jpeg, input.appendingPathComponent("photo-landscape.jpg"), [kCGImageDestinationLossyCompressionQuality: 0.95])
write(photo(1200, 1800, seed: 2), .jpeg, input.appendingPathComponent("photo-portrait.jpg"), [kCGImageDestinationLossyCompressionQuality: 0.92])
write(photo(6000, 4000, seed: 3), .jpeg, input.appendingPathComponent("huge-24mp.jpg"), [kCGImageDestinationLossyCompressionQuality: 0.9])
write(photo(1600, 900, seed: 4), .jpeg, input.appendingPathComponent("rotated-exif6.jpg"), [
    kCGImagePropertyOrientation: 6, kCGImageDestinationLossyCompressionQuality: 0.9,
    kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFOrientation: 6, kCGImagePropertyTIFFArtist: "Sample Artist", kCGImagePropertyTIFFCopyright: "© Sample"],
    kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 0.12, kCGImagePropertyGPSLongitudeRef: "W"]])
write(photo(800, 600, seed: 5), .jpeg, input.appendingPathComponent("rotated-exif8.jpg"), [kCGImagePropertyOrientation: 8, kCGImageDestinationLossyCompressionQuality: 0.9])
write(graphic(1024, 512, colors: 7, alpha: true), .png, input.appendingPathComponent("logo-transparent.png"))
write(graphic(1920, 1080, colors: 40, alpha: false), .png, input.appendingPathComponent("screenshot-like.png"))
do {
    let ctx = context(900, 900, alpha: true)
    ctx.clear(CGRect(x: 0, y: 0, width: 900, height: 900))
    ctx.addEllipse(in: CGRect(x: 50, y: 50, width: 800, height: 800)); ctx.clip()
    ctx.draw(photo(900, 900, seed: 6), in: CGRect(x: 0, y: 0, width: 900, height: 900))
    write(ctx.makeImage()!, .png, input.appendingPathComponent("photo-transparent.png"))
}
write(photo(1400, 1000, seed: 7, space: CGColorSpace(name: CGColorSpace.displayP3)!), .png, input.appendingPathComponent("display-p3.png"))
write(photo(1000, 700, seed: 8), .heic, input.appendingPathComponent("iphone-like.heic"), [kCGImageDestinationLossyCompressionQuality: 0.85])
write(photo(1000, 700, seed: 9), .tiff, input.appendingPathComponent("scan.tiff"))
do {
    let url = input.appendingPathComponent("animation.gif")
    let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 6, nil)!
    CGImageDestinationSetProperties(d, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for i in 0..<6 {
        let ctx = context(240, 160, alpha: false)
        ctx.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
        ctx.setFillColor(CGColor(red: 1, green: 0.8, blue: 0.1, alpha: 1)); ctx.fillEllipse(in: CGRect(x: 20 + i * 30, y: 50, width: 60, height: 60))
        CGImageDestinationAddImage(d, ctx.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(d))
}
try! """
<svg xmlns="http://www.w3.org/2000/svg" width="200" height="120" viewBox="0 0 200 120"><rect width="200" height="120" rx="16" fill="#1f6feb"/><text x="100" y="72" font-size="40" text-anchor="middle" fill="#fff" font-family="Helvetica">SVG</text></svg>
""".data(using: .utf8)!.write(to: input.appendingPathComponent("badge.svg"))
try! Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x02, 0x03]).write(to: input.appendingPathComponent("corrupted.jpg"))

// MARK: - Run

let files = try! FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
let fingerprints = Dictionary(uniqueKeysWithValues: files.map { ($0, fingerprint($0)) })
var items: [BatchItem] = []
var unreadable: [(URL, String)] = []
for url in files {
    do {
        let analysis = try ImageAnalyzer().analyze(url: url)
        items.append(BatchItem(id: UUID(), job: ProcessingJob(sourceURL: url, importRoot: base.appendingPathComponent("input"), analysis: analysis)))
    } catch {
        unreadable.append((url, (error as? LocalizedError)?.errorDescription ?? "\(error)"))
    }
}

var settings = OptimizationSettings()
settings.auto = AutoOptimizeSettings(isEnabled: true, maxWidth: 2560, maxHeight: 2560)
settings.output = OutputSettings(destination: .customFolder, preserveFolderStructure: true, suffix: .web)
let context = PipelineContext(settings: settings, capabilities: .current, acknowledgedWarnings: [], customFolderURL: output)
let report = PreflightReport.make(items: items, context: context)

print("\nCapabilities: WebP \(EncoderCapabilities.current.encoderDescription(for: .webp)), AVIF \(EncoderCapabilities.current.canEncodeAVIF ? "yes" : "no"), HEIC \(EncoderCapabilities.current.canEncodeHEIC ? "yes" : "no")")
print("Preflight: \(items.count) items, confirmations needed: \(report.confirmations.map { "\($0.key.rawValue)×\($0.value)" }.sorted().joined(separator: ", ").ifEmpty("none"))")
print("Running Auto optimize (max 2560×2560) → \(output.path)\n")

let processor = BatchProcessor(maxConcurrency: 3)
var results: [ProcessingResult] = []
var summary: BatchSummary?
let semaphore = DispatchSemaphore(value: 0)
Task {
    for await event in processor.run(items: items, context: context) {
        switch event {
        case .itemFinished(_, let result): results.append(result)
        case .finished(let s): summary = s
        default: break
        }
    }
    semaphore.signal()
}
semaphore.wait()

// MARK: - Report

func pad(_ s: String, _ n: Int) -> String { s.count >= n ? String(s.prefix(n)) : s + String(repeating: " ", count: n - s.count) }
print(pad("File", 24) + pad("In", 22) + pad("Out", 24) + pad("Size", 30) + "Status")
var problems: [String] = []
for result in results.sorted(by: { $0.sourceURL.lastPathComponent < $1.sourceURL.lastPathComponent }) {
    let name = result.sourceURL.lastPathComponent
    let inDesc = "\(result.inputFormat.displayName) \(result.originalPixelSize)"
    let outDesc = "\(result.outputFormat.displayName) \(result.outputPixelSize)"
    let size = "\(ByteFormatting.string(result.originalSize)) → \(ByteFormatting.string(result.optimizedSize)) \(ByteFormatting.percent(result.reductionPercent))"
    print(pad(name, 24) + pad(inDesc, 22) + pad(outDesc, 24) + pad(size, 30) + result.status.displayName + (result.outputURL.map { "  \($0.lastPathComponent)" } ?? ""))
    if let url = result.outputURL, result.status.isSuccess {
        do {
            try OutputValidator.validate(url: url)
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
            let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0, h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
            if PixelSize(width: w, height: h) != result.outputPixelSize { problems.append("\(name): file is \(w)×\(h) but result says \(result.outputPixelSize)") }
            if max(w, h) > 2560 { problems.append("\(name): longest side \(max(w, h)) exceeds 2560") }
            if result.inputFormat == .gif && CGImageSourceGetCount(source) < 2 { problems.append("\(name): animation lost") }
            if name.contains("transparent") && (props[kCGImagePropertyHasAlpha] as? Bool) != true { problems.append("\(name): transparency lost") }
            if name.contains("rotated") && (props[kCGImagePropertyOrientation] as? Int ?? 1) != 1 { problems.append("\(name): orientation tag still present") }
            if props[kCGImagePropertyGPSDictionary] != nil { problems.append("\(name): GPS data leaked") }
            if (try? Data(contentsOf: url).count).map(Int64.init) != result.optimizedSize { problems.append("\(name): reported size differs from file size") }
        } catch {
            problems.append("\(name): output does not open — \(error)")
        }
    }
    if case .failed(let message) = result.status { problems.append("\(name): failed — \(message)") }
    if case .skipped(let reason) = result.status { print("    skipped: \(reason)") }
}
for (url, message) in unreadable { print(pad(url.lastPathComponent, 24) + "rejected at import: \(message)") }

print("\nOriginals unchanged: ", terminator: "")
let changed = files.filter { fingerprint($0) != fingerprints[$0] }
print(changed.isEmpty ? "yes (\(files.count) files verified)" : "NO — \(changed.map(\.lastPathComponent))")
if !changed.isEmpty { problems.append("source files modified: \(changed.map(\.lastPathComponent))") }

if let summary {
    print("Summary: \(summary.processed) processed, \(summary.succeeded) optimized, \(summary.keptOriginal) kept, \(summary.skipped) skipped, \(summary.failed) failed; \(ByteFormatting.string(summary.totalOriginalSize)) → \(ByteFormatting.string(summary.totalOptimizedSize)) (saved \(ByteFormatting.string(summary.totalSaved)), \(ByteFormatting.percent(summary.averageReductionPercent))) in \(String(format: "%.1f", summary.duration)) s")
}
if problems.isEmpty {
    print("\nVERIFICATION PASSED")
    exit(0)
} else {
    print("\nVERIFICATION FAILED:")
    problems.forEach { print("  • \($0)") }
    exit(1)
}

extension String { func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self } }
