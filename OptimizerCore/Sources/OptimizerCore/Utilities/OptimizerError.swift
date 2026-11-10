import Foundation

public enum OptimizerError: LocalizedError, Sendable, Equatable {
    case fileNotFound(URL)
    case unreadable(URL)
    case unsupportedFormat(URL, String)
    case corrupted(URL)
    case encodingFailed(OutputFormat, String)
    case encoderUnavailable(OutputFormat)
    case destinationNotWritable(URL)
    case outputExists(URL)
    case needsConfirmation(ItemWarning)
    case invalidResizeSettings(String)
    case outputValidationFailed(URL)
    case noCustomFolder
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url): return "“\(url.lastPathComponent)” could not be found."
        case .unreadable(let url): return "“\(url.lastPathComponent)” could not be read."
        case .unsupportedFormat(let url, let type): return "“\(url.lastPathComponent)” is not a supported image (\(type))."
        case .corrupted(let url): return "“\(url.lastPathComponent)” is damaged or incomplete."
        case .encodingFailed(let format, let reason): return "Encoding to \(format.displayName) failed: \(reason)"
        case .encoderUnavailable(let format): return "This Mac cannot encode \(format.displayName)."
        case .destinationNotWritable(let url): return "The folder “\(url.lastPathComponent)” is not writable."
        case .outputExists(let url): return "“\(url.lastPathComponent)” already exists."
        case .needsConfirmation(let warning): return warning.title
        case .invalidResizeSettings(let message): return message
        case .outputValidationFailed(let url): return "The exported file “\(url.lastPathComponent)” could not be opened."
        case .noCustomFolder: return "No output folder has been chosen."
        case .cancelled: return "Cancelled."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .fileNotFound: return "The file was moved or deleted after it was added. Remove it from the queue."
        case .unreadable: return "Check that you have permission to read the file and that the disk is connected."
        case .unsupportedFormat: return "Convert the file to JPEG, PNG, HEIC, TIFF, GIF, WebP or SVG first."
        case .corrupted: return "Try opening the file in Preview. If it fails there too, re-export it from its source."
        case .encodingFailed: return "Try a different output format or quality."
        case .encoderUnavailable(let format):
            return format == .avif ? "AVIF encoding needs macOS 14 or later. Choose WebP instead." : "Choose a different output format."
        case .destinationNotWritable: return "Choose another output folder or grant access to this one in the Output section."
        case .outputExists: return "Change the conflict setting in the Output section to rename or overwrite."
        case .needsConfirmation(let warning): return warning.detail
        case .invalidResizeSettings: return "Fix the values in the Resize section."
        case .outputValidationFailed: return "The output was removed. Try a different format."
        case .noCustomFolder: return "Pick a folder in the Output section."
        case .cancelled: return nil
        }
    }
}
