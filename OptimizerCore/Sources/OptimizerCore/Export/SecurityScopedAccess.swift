import Foundation

/// Helpers for App Sandbox folder access. Bookmarks let the app reopen a folder the user
/// chose in a previous launch without asking again.
public enum SecurityScopedAccess {
    public static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public static func resolve(_ bookmark: Data) -> (url: URL, isStale: Bool)? {
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        return (url, isStale)
    }

    /// Runs `body` while the URL's security scope is active. Safe to call for URLs without a scope.
    public static func withAccess<T>(to url: URL?, _ body: () throws -> T) rethrows -> T {
        let started = url?.startAccessingSecurityScopedResource() ?? false
        defer { if started { url?.stopAccessingSecurityScopedResource() } }
        return try body()
    }

    /// Whether the process can currently create files in the folder (false inside the sandbox
    /// until the user grants access).
    public static func canWrite(to folder: URL) -> Bool {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue && fileManager.isWritableFile(atPath: folder.path)
        }
        // Folder does not exist yet: check the nearest existing ancestor.
        var parent = folder.deletingLastPathComponent()
        while parent.path != "/" && !fileManager.fileExists(atPath: parent.path) {
            parent = parent.deletingLastPathComponent()
        }
        return fileManager.isWritableFile(atPath: parent.path)
    }
}
