import AppKit

/// Receives files opened from Finder ("Open With" or drag onto the Dock icon) and hands them to the queue.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var importHandler: (([URL]) -> Void)?

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            AppDelegate.importHandler?(urls)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
