import Foundation

/// Tiny JSON-in-UserDefaults helper so every stored value is versioned and typed.
enum Persistence {
    static let settingsKey = "optimizationSettings.v1"
    static let presetsKey = "customPresets.v1"
    static let preferencesKey = "appPreferences.v1"
    static let bookmarksKey = "folderBookmarks.v1"
    static let viewModeKey = "queueViewMode.v1"
    static let inspectorKey = "showInspector.v1"
    static let sidebarWidthKey = "sidebarWidth.v1"
    static let inspectorWidthKey = "inspectorWidth.v1"

    static func load<T: Decodable>(_ type: T.Type, key: String, defaults: UserDefaults = .standard) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, key: String, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    static func remove(key: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}
