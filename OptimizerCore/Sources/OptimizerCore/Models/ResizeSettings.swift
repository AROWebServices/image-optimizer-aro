import Foundation

public struct PixelSize: Hashable, Codable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
    }

    public var description: String { "\(width) × \(height)" }
    public var pixelCount: Int { width * height }
    public var megapixels: Double { Double(pixelCount) / 1_000_000 }
    public var aspectRatio: Double { height == 0 ? 1 : Double(width) / Double(height) }
    public var longestSide: Int { max(width, height) }
}

public struct ResizeSettings: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable, Identifiable {
        case none, fit, fill, exact, percentage

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .none: return "Original size"
            case .fit: return "Fit within"
            case .fill: return "Fill and crop"
            case .exact: return "Exact size"
            case .percentage: return "Percentage"
            }
        }

        public var explanation: String {
            switch self {
            case .none: return "Images keep their pixel dimensions."
            case .fit: return "Scales each image so it fits inside the width and height. Aspect ratio is always kept; leave a field empty for no limit."
            case .fill: return "Scales each image to cover the width and height, then crops the centre. Aspect ratio is kept, edges are cut."
            case .exact: return "Resizes to exactly the width and height. With the aspect lock on, the missing side is derived per image."
            case .percentage: return "Scales every image by the same percentage of its original size."
            }
        }
    }

    public var mode: Mode
    public var width: Int?
    public var height: Int?
    public var percentage: Double
    public var lockAspectRatio: Bool
    public var onlyShrink: Bool
    public var sharpenAfterResize: Bool

    public init(mode: Mode = .none,
                width: Int? = nil,
                height: Int? = nil,
                percentage: Double = 100,
                lockAspectRatio: Bool = true,
                onlyShrink: Bool = true,
                sharpenAfterResize: Bool = false) {
        self.mode = mode
        self.width = width
        self.height = height
        self.percentage = percentage
        self.lockAspectRatio = lockAspectRatio
        self.onlyShrink = onlyShrink
        self.sharpenAfterResize = sharpenAfterResize
    }

    /// Presets for the longest edge. `0` means "original size".
    public static let longestEdgePresets: [Int] = [0, 3840, 2560, 1920, 1600, 1200, 800, 640]

    public static func preset(longestEdge: Int) -> ResizeSettings {
        if longestEdge <= 0 { return ResizeSettings(mode: .none) }
        return ResizeSettings(mode: .fit, width: longestEdge, height: longestEdge)
    }

    /// The preset this configuration corresponds to, if any.
    public var matchingLongestEdgePreset: Int? {
        if mode == .none { return 0 }
        guard mode == .fit, let width, let height, width == height,
              ResizeSettings.longestEdgePresets.contains(width) else { return nil }
        return width
    }

    public var isActive: Bool {
        switch mode {
        case .none: return false
        case .fit: return width != nil || height != nil
        case .fill, .exact: return width != nil || height != nil
        case .percentage: return percentage != 100
        }
    }

    /// Validation message when the settings cannot be applied.
    public var validationMessage: String? {
        switch mode {
        case .none: return nil
        case .fit:
            if width == nil && height == nil { return "Enter a maximum width, height or both." }
        case .fill:
            if width == nil || height == nil { return "Fill and crop needs both a width and a height." }
        case .exact:
            if width == nil && height == nil { return "Enter a width, a height or both." }
            if !lockAspectRatio && (width == nil || height == nil) { return "Exact size without the aspect lock needs both a width and a height." }
        case .percentage:
            if percentage <= 0 || percentage > 1000 { return "Percentage must be between 1 and 1000." }
        }
        if let width, width <= 0 { return "Width must be at least 1 pixel." }
        if let height, height <= 0 { return "Height must be at least 1 pixel." }
        return nil
    }
}
