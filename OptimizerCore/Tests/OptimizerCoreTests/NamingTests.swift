import Testing
import Foundation
@testable import OptimizerCore

@Suite("Output naming and conflicts")
struct NamingTests {
    let dir = TestImages.temporaryDirectory()

    var source: URL { dir.appendingPathComponent("photos/2024/beach.JPG") }

    @Test func suffixAndExtension() throws {
        var settings = OutputSettings(destination: .besideOriginals, suffix: .optimized)
        var namer = OutputNamer(settings: settings)
        #expect(try namer.proposedURL(for: source, importRoot: nil, format: .webp).lastPathComponent == "beach-optimized.webp")
        settings.suffix = .web
        namer = OutputNamer(settings: settings)
        #expect(namer.fileName(for: source, format: .jpeg) == "beach-web.jpg")
        settings.suffix = .custom
        settings.customSuffix = "_sm/all:"
        namer = OutputNamer(settings: settings)
        #expect(namer.fileName(for: source, format: .png) == "beach_small.png")
        settings.suffix = .none
        #expect(OutputNamer(settings: settings).fileName(for: source, format: .png) == "beach.png")
    }

    @Test func subfolderPreservesStructureFromImportRoot() throws {
        let root = dir.appendingPathComponent("photos")
        let namer = OutputNamer(settings: OutputSettings(destination: .optimizedSubfolder, preserveFolderStructure: true))
        let url = try namer.proposedURL(for: source, importRoot: root, format: .webp)
        #expect(url.path.hasSuffix("photos/optimized/2024/beach-optimized.webp"))
        let flat = OutputNamer(settings: OutputSettings(destination: .optimizedSubfolder, preserveFolderStructure: false))
        #expect(try flat.proposedURL(for: source, importRoot: root, format: .webp).path.hasSuffix("photos/2024/optimized/beach-optimized.webp"))
        let single = try namer.proposedURL(for: source, importRoot: nil, format: .webp)
        #expect(single.path.hasSuffix("photos/2024/optimized/beach-optimized.webp"))
    }

    @Test func customFolderWithStructure() throws {
        let root = dir.appendingPathComponent("photos")
        let out = dir.appendingPathComponent("export")
        let namer = OutputNamer(settings: OutputSettings(destination: .customFolder, preserveFolderStructure: true), customFolder: out)
        #expect(try namer.proposedURL(for: source, importRoot: root, format: .avif).path.hasSuffix("export/2024/beach-optimized.avif"))
        let missing = OutputNamer(settings: OutputSettings(destination: .customFolder), customFolder: nil)
        #expect(throws: OptimizerError.noCustomFolder) { try missing.proposedURL(for: source, importRoot: root, format: .avif) }
    }

    @Test func renameAddsCounterOnExistingAndReservedNames() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("out"), withIntermediateDirectories: true)
        let existing = dir.appendingPathComponent("out/beach-optimized.webp")
        try Data([1]).write(to: existing)
        let namer = OutputNamer(settings: OutputSettings(destination: .customFolder, conflictPolicy: .rename), customFolder: dir.appendingPathComponent("out"))
        let registry = NameRegistry(protectedSources: [source])
        let first = namer.resolve(proposed: existing, source: source, registry: registry)
        #expect(first == .write(dir.appendingPathComponent("out/beach-optimized-2.webp")))
        let second = namer.resolve(proposed: existing, source: source, registry: registry)
        #expect(second == .write(dir.appendingPathComponent("out/beach-optimized-3.webp")))
    }

    @Test func skipPolicy() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("skip"), withIntermediateDirectories: true)
        let existing = dir.appendingPathComponent("skip/a.webp")
        try Data([1]).write(to: existing)
        let namer = OutputNamer(settings: OutputSettings(destination: .customFolder, conflictPolicy: .skip), customFolder: dir.appendingPathComponent("skip"))
        if case .skip = namer.resolve(proposed: existing, source: source, registry: NameRegistry()) {} else { Issue.record("expected skip") }
    }

    @Test func overwriteNeverTouchesSourceFiles() throws {
        let folder = dir.appendingPathComponent("src")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = folder.appendingPathComponent("logo.png")
        try Data([1]).write(to: original)
        let namer = OutputNamer(settings: OutputSettings(destination: .besideOriginals, suffix: .none, conflictPolicy: .overwrite))
        let registry = NameRegistry(protectedSources: [original])
        let resolution = namer.resolve(proposed: original, source: original, registry: registry)
        #expect(resolution == .write(folder.appendingPathComponent("logo-2.png")))
    }

    @Test func replaceOriginalsTargetsSourcePath() throws {
        let folder = dir.appendingPathComponent("rep")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = folder.appendingPathComponent("logo.png")
        try Data([1]).write(to: original)
        let namer = OutputNamer(settings: OutputSettings(destination: .replaceOriginals, suffix: .optimized))
        #expect(namer.settings.effectiveSuffix.isEmpty)
        let proposed = try namer.proposedURL(for: original, importRoot: nil, format: .png)
        #expect(proposed == original)
        #expect(namer.resolve(proposed: proposed, source: original, registry: NameRegistry(protectedSources: [original])) == .replaceSource(original))
    }

    @Test func byteFormatting() {
        #expect(ByteFormatting.string(999) == "999 bytes")
        #expect(ByteFormatting.string(1500) == "1.50 kB")
        #expect(ByteFormatting.string(2_400_000) == "2.40 MB")
        #expect(ByteFormatting.string(2_400_000, style: .binary) == "2.29 MiB")
        #expect(ByteFormatting.string(123_456_789) == "123 MB")
        #expect(ByteFormatting.percent(42.4) == "−42%")
        #expect(ByteFormatting.percent(-5) == "+5%")
    }
}
