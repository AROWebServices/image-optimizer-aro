import SwiftUI
import OptimizerCore

/// Before/after viewer with side-by-side, split and press-to-compare modes, plus zoom up to 400 %.
struct ComparisonView: View {
    @Environment(AppModel.self) private var model
    let item: QueueItem

    enum Mode: String, CaseIterable, Identifiable {
        case sideBySide, split, toggle
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sideBySide: return "Side by side"
            case .split: return "Split"
            case .toggle: return "Press to compare"
            }
        }
    }

    @State private var mode: Mode = .split
    /// nil means "fit to view".
    @State private var zoom: Double?
    @State private var splitFraction: Double = 0.5
    @State private var showingOriginal = false

    private var preview: PreviewModel { model.preview }

    var body: some View {
        GroupBox {
            VStack(spacing: 8) {
                controls
                viewport
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                caption
            }
        } label: {
            HStack {
                Text("Before / after")
                if preview.isRendering {
                    ProgressView().controlSize(.mini)
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Comparison mode")
            Spacer()
            Button("Fit") { zoom = nil }
                .disabled(zoom == nil)
            Button("100%") { zoom = 1 }
                .disabled(zoom == 1)
                .help("Show actual pixels")
            Menu {
                ForEach([0.25, 0.5, 1.0, 2.0, 4.0], id: \.self) { level in
                    Button("\(Int(level * 100))%") { zoom = level }
                }
            } label: {
                Text(zoomLabel)
                    .monospacedDigit()
                    .frame(width: 48)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Zoom level")
        }
        .controlSize(.small)
    }

    private var zoomLabel: String {
        if let zoom { return "\(Int((zoom * 100).rounded()))%" }
        return "Fit"
    }

    @ViewBuilder
    private var viewport: some View {
        GeometryReader { geometry in
            if let optimized = preview.optimized, let original = preview.original {
                let base = CGSize(width: optimized.width, height: optimized.height)
                let fitScale = min(geometry.size.width / base.width, geometry.size.height / base.height, 1)
                let scale = zoom ?? fitScale
                let displaySize = CGSize(width: base.width * scale, height: base.height * scale)
                ScrollView([.horizontal, .vertical]) {
                    content(original: original, optimized: optimized, size: displaySize, scale: scale)
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                }
                .background(Checkerboard(squareSize: 10))
            } else {
                ZStack {
                    Checkerboard(squareSize: 10)
                    if let message = preview.errorMessage {
                        InlineNote(text: message, systemImage: "exclamationmark.triangle.fill", tint: .red).padding()
                    } else {
                        ProgressView("Rendering preview…")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func content(original: CGImage, optimized: CGImage, size: CGSize, scale: CGFloat) -> some View {
        let interpolation: Image.Interpolation = scale >= 1 ? .none : .high
        switch mode {
        case .sideBySide:
            HStack(spacing: 4) {
                VStack(spacing: 2) {
                    image(original, size: size, interpolation: interpolation)
                    Text("Original").font(.caption2).foregroundStyle(.secondary)
                }
                VStack(spacing: 2) {
                    image(optimized, size: size, interpolation: interpolation)
                    Text("Optimized").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(4)
        case .split:
            ZStack(alignment: .leading) {
                image(optimized, size: size, interpolation: interpolation)
                image(original, size: size, interpolation: interpolation)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: size.width * splitFraction)
                    }
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: size.height)
                    .shadow(radius: 2)
                    .offset(x: size.width * splitFraction - 1)
                    .accessibilityHidden(true)
                HStack {
                    Text("Original").font(.caption2.weight(.semibold)).padding(4).background(.black.opacity(0.5), in: Capsule()).foregroundStyle(.white)
                    Spacer()
                    Text("Optimized").font(.caption2.weight(.semibold)).padding(4).background(.black.opacity(0.5), in: Capsule()).foregroundStyle(.white)
                }
                .padding(6)
                .frame(width: size.width)
                .allowsHitTesting(false)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        splitFraction = min(1, max(0, value.location.x / size.width))
                    }
            )
            .accessibilityLabel("Split comparison, drag to move the divider")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: splitFraction = min(1, splitFraction + 0.1)
                case .decrement: splitFraction = max(0, splitFraction - 0.1)
                @unknown default: break
                }
            }
        case .toggle:
            VStack(spacing: 4) {
                image(showingOriginal ? original : optimized, size: size, interpolation: interpolation)
                Text(showingOriginal ? "Original" : "Optimized — press and hold to see the original")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.05, maximumDistance: 50, perform: {}, onPressingChanged: { pressing in
                showingOriginal = pressing
            })
            .accessibilityLabel(showingOriginal ? "Showing original" : "Showing optimized")
            .accessibilityAction(named: "Toggle original") { showingOriginal.toggle() }
        }
    }

    private func image(_ cgImage: CGImage, size: CGSize, interpolation: Image.Interpolation) -> some View {
        Image(decorative: cgImage, scale: 1)
            .resizable()
            .interpolation(interpolation)
            .frame(width: size.width, height: size.height)
    }

    private var caption: some View {
        HStack {
            if let analysis = item.analysis {
                Text("Original \(model.format(analysis.fileSize))")
            }
            if let size = preview.estimatedSize, let analysis = item.analysis {
                Text("·")
                Text("Optimized \(model.format(size))")
                ReductionText(percent: analysis.fileSize > 0 ? (1 - Double(size) / Double(analysis.fileSize)) * 100 : 0)
            }
            Spacer()
            if let optimized = preview.optimized, let outputSize = preview.outputSize, optimized.width < outputSize.width {
                Text("Preview downscaled to \(optimized.width) px").foregroundStyle(.secondary)
            } else if let outputSize = preview.outputSize {
                Text("Rendered at \(outputSize.description)").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .lineLimit(1)
    }
}
