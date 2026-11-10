import AppKit
import Foundation
import Observation
import OptimizerCore

/// Keeps track of folders the user has granted access to. Inside the App Sandbox the app can
/// only write where the user pointed it, so this store holds security-scoped bookmarks and
/// asks for access with an open panel when an export needs a folder it cannot write to yet.
@Observable @MainActor
final class FolderAccessStore {
    private(set) var grantedFolders: [URL] = []
    private var bookmarks: [String: Data] {
        didSet { Persistence.save(bookmarks, key: Persistence.bookmarksKey) }
    }
    /// URLs whose security scope is currently open (bookmarked folders and folders imported this session).
    private var openScopes: Set<URL> = []

    init() {
        bookmarks = Persistence.load([String: Data].self, key: Persistence.bookmarksKey) ?? [:]
        for (_, data) in bookmarks {
            if let resolved = SecurityScopedAccess.resolve(data) {
                if resolved.url.startAccessingSecurityScopedResource() { openScopes.insert(resolved.url) }
                grantedFolders.append(resolved.url)
            }
        }
        grantedFolders.sort { $0.path < $1.path }
    }

    /// Remember a folder the user picked in an open panel or dropped on the window.
    func grant(_ url: URL, persist: Bool = true) {
        let folder = url.standardizedFileURL
        if !openScopes.contains(folder), folder.startAccessingSecurityScopedResource() {
            openScopes.insert(folder)
        }
        if persist, let data = try? SecurityScopedAccess.bookmark(for: folder) {
            bookmarks[folder.path] = data
            if !grantedFolders.contains(folder) {
                grantedFolders.append(folder)
                grantedFolders.sort { $0.path < $1.path }
            }
        }
    }

    func revoke(_ url: URL) {
        bookmarks.removeValue(forKey: url.path)
        grantedFolders.removeAll { $0 == url }
        if openScopes.remove(url) != nil { url.stopAccessingSecurityScopedResource() }
    }

    func resolve(bookmark: Data?) -> URL? {
        guard let bookmark, let resolved = SecurityScopedAccess.resolve(bookmark) else { return nil }
        grant(resolved.url, persist: resolved.isStale)
        return resolved.url
    }

    /// Nearest existing ancestor of a folder that may not exist yet.
    static func existingAncestor(of folder: URL) -> URL {
        var current = folder.standardizedFileURL
        while !FileManager.default.fileExists(atPath: current.path), current.pathComponents.count > 1 {
            current = current.deletingLastPathComponent()
        }
        return current
    }

    /// Asks the user to grant access to `folder` (or its nearest existing parent). Returns true on success.
    func requestAccess(to folder: URL) async -> Bool {
        let target = FolderAccessStore.existingAncestor(of: folder)
        if SecurityScopedAccess.canWrite(to: folder) { return true }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = target
        panel.prompt = "Grant Access"
        panel.title = "Allow saving to “\(target.lastPathComponent)”"
        panel.message = "Image Optimizer ARO needs permission to save optimized files in “\(target.lastPathComponent)”. Select the folder to allow it."
        let response = await panel.begin()
        guard response == .OK, let chosen = panel.url else { return false }
        grant(chosen)
        return SecurityScopedAccess.canWrite(to: folder)
    }
}
