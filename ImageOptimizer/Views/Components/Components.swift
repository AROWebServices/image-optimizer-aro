import SwiftUI
import OptimizerCore

/// Grey checkerboard so transparent regions are visible.
struct Checkerboard: View {
    var squareSize: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            let light = Color(nsColor: .quaternaryLabelColor).opacity(0.35)
            let dark = Color(nsColor: .quaternaryLabelColor).opacity(0.75)
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var column = 0
                while x < size.width {
                    let rect = CGRect(x: x, y: y, width: squareSize, height: squareSize)
                    context.fill(Path(rect), with: .color((row + column) % 2 == 0 ? light : dark))
                    x += squareSize
                    column += 1
                }
                y += squareSize
                row += 1
            }
        }
        .accessibilityHidden(true)
    }
}

struct ThumbnailView: View {
    var image: CGImage?
    var isAnimated = false
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
            Checkerboard(squareSize: 6)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(2)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
            if isAnimated {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("GIF")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                            .foregroundStyle(.white)
                            .padding(3)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct FormatBadge: View {
    var text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(tint)
    }
}

/// Coloured reduction percentage.
struct ReductionText: View {
    var percent: Double

    var body: some View {
        Text(ByteFormatting.percent(percent))
            .font(.callout.weight(.semibold).monospacedDigit())
            .foregroundStyle(percent >= 1 ? Color.green : (percent < -1 ? Color.orange : Color.secondary))
            .accessibilityLabel(percent >= 0 ? "\(Int(percent)) percent smaller" : "\(Int(-percent)) percent larger")
    }
}

struct WarningLabel: View {
    var warning: ItemWarning
    var showDetail = true

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(warning.title).font(.callout.weight(.medium))
                if showDetail {
                    Text(warning.detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: warning.requiresConfirmation ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(warning.requiresConfirmation ? Color.orange : Color.accentColor)
        }
    }
}

struct InlineNote: View {
    var text: String
    var systemImage: String = "info.circle"
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(tint)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct StatusBadge: View {
    var status: QueueItem.Status

    var body: some View {
        HStack(spacing: 4) {
            if status.isBusy {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: status.symbolName)
                    .foregroundStyle(color)
            }
            Text(status.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(status.label)
    }

    private var color: Color {
        switch status {
        case .done: return .green
        case .keptOriginal: return .blue
        case .failed, .unreadable: return .red
        case .skipped: return .orange
        default: return .secondary
        }
    }
}

extension OutputFormat {
    var tint: Color {
        switch self {
        case .webp: return .green
        case .avif: return .purple
        case .jpeg: return .orange
        case .png: return .blue
        case .heic: return .pink
        case .gif: return .teal
        }
    }
}

extension ImageFormat {
    var tint: Color {
        switch self {
        case .webp: return .green
        case .avif: return .purple
        case .jpeg: return .orange
        case .png: return .blue
        case .heic, .heif: return .pink
        case .gif: return .teal
        case .svg: return .indigo
        default: return .secondary
        }
    }
}
