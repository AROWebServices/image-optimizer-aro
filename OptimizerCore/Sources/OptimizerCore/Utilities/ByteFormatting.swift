import Foundation

public enum ByteUnitStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    /// 1 kB = 1000 bytes (what Finder shows).
    case decimal
    /// 1 KiB = 1024 bytes.
    case binary

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .decimal: return "Decimal (kB, MB — like Finder)"
        case .binary: return "Binary (KiB, MiB)"
        }
    }
}

public enum ByteFormatting {
    public static func string(_ bytes: Int64, style: ByteUnitStyle = .decimal) -> String {
        let units: [String]
        let base: Double
        switch style {
        case .decimal:
            units = ["bytes", "kB", "MB", "GB", "TB"]
            base = 1000
        case .binary:
            units = ["bytes", "KiB", "MiB", "GiB", "TiB"]
            base = 1024
        }
        if bytes < 0 { return "−" + string(-bytes, style: style) }
        var value = Double(bytes)
        var index = 0
        while value >= base && index < units.count - 1 {
            value /= base
            index += 1
        }
        if index == 0 { return "\(bytes) \(units[0])" }
        let digits = value < 10 ? 2 : (value < 100 ? 1 : 0)
        return String(format: "%.\(digits)f %@", value, units[index])
    }

    public static func percent(_ value: Double) -> String {
        if abs(value) < 0.05 { return "0%" }
        return String(format: value < 0 ? "+%.0f%%" : "−%.0f%%", abs(value))
    }
}
