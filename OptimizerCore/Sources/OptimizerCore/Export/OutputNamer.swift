import Foundation

/// Tracks output paths claimed during a batch so two sources never race for the same name,
/// and protects every source file from being overwritten.
public final class NameRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var reserved = Set<String>()
    private let protected: Set<String>

    public init(protectedSources: [URL] = []) {
        protected = Set(protectedSources.map { NameRegistry.key($0) })
    }

    static func key(_ url: URL) -> String { url.standardizedFileURL.path.lowercased() }

    public func isProtected(_ url: URL) -> Bool { protected.contains(NameRegistry.key(url)) }

    /// Returns false when the path is already claimed by another item in this batch.
    public func reserve(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return reserved.insert(NameRegistry.key(url)).inserted
    }

    public func isReserved(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return reserved.contains(NameRegistry.key(url))
    }
}

/// Decides where an output file goes and what it is called.
public struct OutputNamer: Sendable {
    public var settings: OutputSettings
    public var customFolder: URL?

    public init(settings: OutputSettings, customFolder: URL? = nil) {
        self.settings = settings
        self.customFolder = customFolder
    }

    /// Path components between the import root and the file's folder, e.g. ["2024", "June"].
    public static func relativeDirectory(of source: URL, within root: URL?) -> [String] {
        guard let root else { return [] }
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = source.standardizedFileURL.deletingLastPathComponent().pathComponents
        guard fileComponents.count >= rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents else { return [] }
        return Array(fileComponents.dropFirst(rootComponents.count))
    }

    public func destinationFolder(for source: URL, importRoot: URL?) throws -> URL {
        let sourceFolder = source.deletingLastPathComponent()
        let relative = settings.preserveFolderStructure ? OutputNamer.relativeDirectory(of: source, within: importRoot) : []
        switch settings.destination {
        case .besideOriginals, .replaceOriginals:
            return sourceFolder
        case .optimizedSubfolder:
            if let importRoot, settings.preserveFolderStructure {
                var folder = importRoot.appendingPathComponent(settings.effectiveSubfolderName, isDirectory: true)
                for component in relative { folder.appendPathComponent(component, isDirectory: true) }
                return folder
            }
            return sourceFolder.appendingPathComponent(settings.effectiveSubfolderName, isDirectory: true)
        case .customFolder:
            guard let customFolder else { throw OptimizerError.noCustomFolder }
            var folder = customFolder
            for component in relative { folder.appendPathComponent(component, isDirectory: true) }
            return folder
        }
    }

    public func fileName(for source: URL, format: OutputFormat) -> String {
        let stem = source.deletingPathExtension().lastPathComponent
        return stem + settings.effectiveSuffix + "." + format.fileExtension
    }

    /// The ideal output location before conflicts are considered.
    public func proposedURL(for source: URL, importRoot: URL?, format: OutputFormat) throws -> URL {
        try destinationFolder(for: source, importRoot: importRoot).appendingPathComponent(fileName(for: source, format: format))
    }

    public enum Resolution: Sendable, Hashable {
        case write(URL)
        /// The output path is the source path itself (only when replacing originals).
        case replaceSource(URL)
        case skip(reason: String)
    }

    /// Applies the conflict policy. Source files are never overwritten unless the destination is "replace originals".
    public func resolve(proposed: URL, source: URL, registry: NameRegistry, fileManager: FileManager = .default) -> Resolution {
        let sameAsSource = NameRegistry.key(proposed) == NameRegistry.key(source)
        if settings.destination == .replaceOriginals && sameAsSource {
            _ = registry.reserve(proposed)
            return .replaceSource(proposed)
        }
        let exists = fileManager.fileExists(atPath: proposed.path)
        let claimed = registry.isReserved(proposed)
        let protected = registry.isProtected(proposed) || sameAsSource
        if !exists && !claimed && !protected {
            _ = registry.reserve(proposed)
            return .write(proposed)
        }
        switch settings.conflictPolicy {
        case .skip:
            return .skip(reason: "“\(proposed.lastPathComponent)” already exists")
        case .overwrite where !protected && !claimed:
            _ = registry.reserve(proposed)
            return .write(proposed)
        case .overwrite, .rename:
            let unique = OutputNamer.uniqueURL(for: proposed) { candidate in
                fileManager.fileExists(atPath: candidate.path) || registry.isReserved(candidate) || registry.isProtected(candidate)
            }
            _ = registry.reserve(unique)
            return .write(unique)
        }
    }

    /// photo.webp → photo-2.webp → photo-3.webp …
    public static func uniqueURL(for url: URL, isTaken: (URL) -> Bool) -> URL {
        let folder = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var counter = 2
        while true {
            let candidate = folder.appendingPathComponent("\(stem)-\(counter).\(ext)")
            if !isTaken(candidate) { return candidate }
            counter += 1
        }
    }
}
