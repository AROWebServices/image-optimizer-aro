import Foundation

public struct OutputSettings: Codable, Hashable, Sendable {
    public enum Destination: String, Codable, CaseIterable, Identifiable, Sendable {
        case optimizedSubfolder, besideOriginals, customFolder, replaceOriginals

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .optimizedSubfolder: return "“optimized” subfolder next to originals"
            case .besideOriginals: return "Beside the original files"
            case .customFolder: return "Custom folder"
            case .replaceOriginals: return "Replace the originals"
            }
        }
    }

    public enum Suffix: String, Codable, CaseIterable, Identifiable, Sendable {
        case optimized, web, none, custom

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .optimized: return "-optimized"
            case .web: return "-web"
            case .none: return "No suffix"
            case .custom: return "Custom"
            }
        }
    }

    public enum ConflictPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
        case rename, skip, overwrite

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .rename: return "Add a number (photo-2.webp)"
            case .skip: return "Skip the file"
            case .overwrite: return "Overwrite after confirmation"
            }
        }
    }

    public var destination: Destination
    public var subfolderName: String
    /// Security-scoped bookmark of the custom folder, stored by the app.
    public var customFolderBookmark: Data?
    /// Display path of the custom folder.
    public var customFolderPath: String?
    public var preserveFolderStructure: Bool
    public var suffix: Suffix
    public var customSuffix: String
    public var conflictPolicy: ConflictPolicy
    /// If the encoded result is not smaller than the source (same format, no resize), keep the original bytes.
    public var keepOriginalIfLarger: Bool

    public init(destination: Destination = .optimizedSubfolder,
                subfolderName: String = "optimized",
                customFolderBookmark: Data? = nil,
                customFolderPath: String? = nil,
                preserveFolderStructure: Bool = true,
                suffix: Suffix = .optimized,
                customSuffix: String = "-small",
                conflictPolicy: ConflictPolicy = .rename,
                keepOriginalIfLarger: Bool = true) {
        self.destination = destination
        self.subfolderName = subfolderName
        self.customFolderBookmark = customFolderBookmark
        self.customFolderPath = customFolderPath
        self.preserveFolderStructure = preserveFolderStructure
        self.suffix = suffix
        self.customSuffix = customSuffix
        self.conflictPolicy = conflictPolicy
        self.keepOriginalIfLarger = keepOriginalIfLarger
    }

    /// The suffix string actually appended to file names. Replacing originals never adds a suffix.
    public var effectiveSuffix: String {
        if destination == .replaceOriginals { return "" }
        switch suffix {
        case .optimized: return "-optimized"
        case .web: return "-web"
        case .none: return ""
        case .custom: return OutputSettings.sanitizedSuffix(customSuffix)
        }
    }

    public var effectiveSubfolderName: String {
        let trimmed = subfolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let safe = trimmed.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return safe.isEmpty ? "optimized" : safe
    }

    public static func sanitizedSuffix(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\")
        let cleaned = raw.unicodeScalars.filter { !forbidden.contains($0) }
        return String(String.UnicodeScalarView(cleaned)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
