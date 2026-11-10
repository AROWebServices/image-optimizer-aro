import SwiftUI
import OptimizerCore

/// Left column: presets and every processing setting, grouped like System Settings.
struct SettingsSidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            PresetSection()
            AutoOptimizeSection()
            FormatSection()
            ResizeSection()
            QualitySection()
            MetadataSection()
            OutputSection()
        }
        .formStyle(.grouped)
        .accessibilityLabel("Optimization settings")
    }
}

// MARK: - Presets

struct PresetSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            Picker("Preset", selection: Binding(
                get: { model.presets.preset(matching: model.settings)?.id },
                set: { id in
                    if let id, let preset = model.presets.all.first(where: { $0.id == id }) { model.apply(preset) }
                })) {
                Text("Custom").tag(Optional<Preset.ID>.none)
                Divider()
                ForEach(model.presets.builtIns) { preset in Text(preset.name).tag(Optional(preset.id)) }
                if !model.presets.customPresets.isEmpty {
                    Divider()
                    ForEach(model.presets.customPresets) { preset in Text(preset.name).tag(Optional(preset.id)) }
                }
            }
            HStack {
                Button("Save as Preset…") { model.promptForPresetName() }
                Button("Manage…") { model.showPresetManager = true }
            }
            .controlSize(.small)
        } header: {
            Text("Presets")
        }
    }
}

// MARK: - Auto optimize

struct AutoOptimizeSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            Toggle("Auto optimize", isOn: $model.settings.auto.isEnabled)
            if model.settings.auto.isEnabled {
                LabeledContent("Maximum size") {
                    HStack(spacing: 4) {
                        TextField("Width", value: $model.settings.auto.maxWidth, format: .number)
                            .frame(width: 64)
                            .accessibilityLabel("Maximum width in pixels")
                        Text("×")
                        TextField("Height", value: $model.settings.auto.maxHeight, format: .number)
                            .frame(width: 64)
                            .accessibilityLabel("Maximum height in pixels")
                        Text("px")
                    }
                    .multilineTextAlignment(.trailing)
                }
                LabeledContent("Quality") {
                    HStack {
                        Slider(value: Binding(get: { Double(model.settings.auto.quality) }, set: { model.settings.auto.quality = Int($0.rounded()) }), in: 1...100)
                            .accessibilityLabel("Auto optimize quality")
                        Text("\(model.settings.auto.quality)").monospacedDigit().frame(width: 28, alignment: .trailing)
                    }
                }
                DisclosureGroup("Advanced") {
                    Toggle("Use best format automatically", isOn: $model.settings.auto.useBestFormatAutomatically)
                    Toggle("Prefer WebP over AVIF", isOn: $model.settings.auto.preferWebPOverAVIF)
                        .disabled(!model.settings.auto.useBestFormatAutomatically || !model.capabilities.canEncodeAVIF)
                    Toggle("Compatibility mode (JPEG, PNG and GIF only)", isOn: $model.settings.auto.compatibilityMode)
                    Text(advancedExplanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("Auto optimize")
        } footer: {
            Text(model.settings.auto.isEnabled
                 ? "Picks a format per image, shrinks anything larger than the maximum size, keeps transparency and animation, removes metadata and never enlarges. Every decision is listed in the inspector. The Format, Resize and Quality sections below are overridden while this is on."
                 : "One switch for sensible results. Turn it on to let the app choose format, size and quality per image.")
        }
    }

    private var advancedExplanation: String {
        if !model.capabilities.canEncodeAVIF {
            return "AVIF encoding is not available on this Mac, so photos become WebP."
        }
        if model.settings.auto.compatibilityMode {
            return "Only JPEG, PNG and GIF are produced for very old browsers."
        }
        if model.settings.auto.allowsAVIF {
            return "Photos become AVIF (smallest, supported by Chrome, Safari 16+, Firefox). Graphics stay WebP or PNG."
        }
        return "Photos become WebP, which every modern browser displays. Switch off “Prefer WebP” to get smaller AVIF files instead."
    }
}

// MARK: - Format

struct FormatSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            Picker("Output format", selection: $model.settings.format) {
                ForEach(FormatSelection.allCases) { selection in
                    if let fixed = selection.fixedFormat, !model.capabilities.supports(fixed) {
                        Text("\(selection.displayName) (not available)").tag(selection)
                    } else {
                        Text(selection.displayName).tag(selection)
                    }
                }
            }
            Text(model.settings.format.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let fixed = model.settings.format.fixedFormat {
                LabeledContent("Encoder", value: model.capabilities.encoderDescription(for: fixed))
                    .font(.caption)
                if fixed == .heic {
                    InlineNote(text: "Most web browsers cannot display HEIC. Use it only for Apple-only workflows.", systemImage: "exclamationmark.triangle", tint: .orange)
                }
                if fixed == .avif, model.capabilities.canEncodeAVIF {
                    InlineNote(text: "System AVIF encoder. No lossless mode; quality is capped at 99.")
                }
            }
            if model.settings.format == .auto {
                Text("Uses the Advanced options in the Auto optimize section to decide whether AVIF may be chosen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Format")
        }
        .disabled(model.settings.auto.isEnabled)
    }
}

// MARK: - Resize

struct ResizeSection: View {
    @Environment(AppModel.self) private var model

    private var selectedPlan: ResizePlan? {
        guard let analysis = model.selectedItem?.analysis else { return nil }
        return Resizer.plan(source: analysis.pixelSize, settings: model.settings.resize)
    }

    var body: some View {
        @Bindable var model = model
        Section {
            Picker("Mode", selection: $model.settings.resize.mode) {
                ForEach(ResizeSettings.Mode.allCases) { mode in Text(mode.displayName).tag(mode) }
            }
            if model.settings.resize.mode != .none {
                Picker("Longest edge", selection: Binding(
                    get: { model.settings.resize.matchingLongestEdgePreset ?? -1 },
                    set: { edge in
                        if edge >= 0 {
                            let onlyShrink = model.settings.resize.onlyShrink
                            let sharpen = model.settings.resize.sharpenAfterResize
                            model.settings.resize = ResizeSettings.preset(longestEdge: edge)
                            model.settings.resize.onlyShrink = onlyShrink
                            model.settings.resize.sharpenAfterResize = sharpen
                        }
                    })) {
                    Text("Custom").tag(-1)
                    ForEach(ResizeSettings.longestEdgePresets.dropFirst(), id: \.self) { edge in
                        Text("\(edge) px").tag(edge)
                    }
                }
            }
            if model.settings.resize.mode == .percentage {
                LabeledContent("Scale") {
                    HStack {
                        Slider(value: $model.settings.resize.percentage, in: 1...200, step: 1)
                            .accessibilityLabel("Scale percentage")
                        TextField("Percent", value: $model.settings.resize.percentage, format: .number.precision(.fractionLength(0)))
                            .frame(width: 52)
                            .multilineTextAlignment(.trailing)
                        Text("%")
                    }
                }
            } else if model.settings.resize.mode != .none {
                LabeledContent(model.settings.resize.mode == .fit ? "Maximum size" : "Size") {
                    HStack(spacing: 4) {
                        TextField("Width", value: $model.settings.resize.width, format: .number, prompt: Text("auto"))
                            .frame(width: 64)
                            .accessibilityLabel("Width in pixels")
                        Button {
                            model.settings.resize.lockAspectRatio.toggle()
                        } label: {
                            Image(systemName: model.settings.resize.lockAspectRatio ? "lock.fill" : "lock.open")
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.settings.resize.mode != .exact)
                        .help(model.settings.resize.mode == .exact
                              ? (model.settings.resize.lockAspectRatio ? "Aspect ratio locked: the missing side is calculated per image" : "Aspect ratio unlocked: images are stretched to exactly this size")
                              : "Fit and Fill always keep the aspect ratio")
                        .accessibilityLabel(model.settings.resize.lockAspectRatio ? "Aspect ratio locked" : "Aspect ratio unlocked")
                        TextField("Height", value: $model.settings.resize.height, format: .number, prompt: Text("auto"))
                            .frame(width: 64)
                            .accessibilityLabel("Height in pixels")
                        Text("px")
                    }
                    .multilineTextAlignment(.trailing)
                }
            }
            if model.settings.resize.mode != .none {
                Toggle("Only shrink images, never enlarge", isOn: $model.settings.resize.onlyShrink)
                Toggle("Sharpen slightly after resizing", isOn: $model.settings.resize.sharpenAfterResize)
            }
            Text(model.settings.resize.mode.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let message = model.settings.resize.validationMessage {
                InlineNote(text: message, systemImage: "exclamationmark.triangle.fill", tint: .red)
            } else if let plan = selectedPlan, let item = model.selectedItem {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.name): \(plan.sourceSize.description) → \(plan.outputSize.description)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if plan.isEnlarging {
                        InlineNote(text: ItemWarning.willEnlarge.title + ". " + ItemWarning.willEnlarge.detail, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                    } else if let note = plan.note {
                        InlineNote(text: note)
                    }
                }
            }
        } header: {
            Text("Resize")
        } footer: {
            Text("High-quality multi-tap resampling. EXIF orientation is applied before resizing, so widths and heights always refer to the upright image.")
        }
        .disabled(model.settings.auto.isEnabled)
    }
}

// MARK: - Quality

struct QualitySection: View {
    @Environment(AppModel.self) private var model

    private var effectiveFormat: OutputFormat? {
        if let fixed = model.settings.format.fixedFormat { return fixed }
        if model.settings.format == .original { return model.selectedItem?.analysis?.format.closestOutputFormat }
        return nil
    }

    var body: some View {
        @Bindable var model = model
        Section {
            Picker("Preset", selection: Binding(
                get: { model.settings.quality.matchingPreset },
                set: { preset in if let preset { model.settings.quality.apply(preset) } })) {
                Text("Custom").tag(Optional<QualitySettings.Preset>.none)
                ForEach(QualitySettings.Preset.allCases) { preset in
                    Text(preset.displayName).tag(Optional(preset))
                }
            }
            let usesSlider = effectiveFormat?.usesQualitySlider ?? true
            if usesSlider {
                LabeledContent("Quality") {
                    HStack {
                        Slider(value: Binding(get: { Double(model.settings.quality.quality) }, set: { model.settings.quality.quality = Int($0.rounded()) }), in: 1...100, step: 1)
                            .disabled(model.settings.quality.lossless && (effectiveFormat?.supportsLossless ?? true))
                            .accessibilityLabel("Quality percent")
                        TextField("Quality", value: Binding(get: { model.settings.quality.quality }, set: { model.settings.quality.quality = min(100, max(1, $0)) }), format: .number)
                            .frame(width: 44)
                            .multilineTextAlignment(.trailing)
                        Text("%")
                    }
                }
            }
            if effectiveFormat?.supportsLossless ?? (model.settings.format == .auto) {
                Toggle("Lossless", isOn: $model.settings.quality.lossless)
            }
            if effectiveFormat == .jpeg || effectiveFormat == nil {
                Toggle("Progressive JPEG", isOn: $model.settings.quality.progressiveJPEG)
            }
            if effectiveFormat == .webp || effectiveFormat == nil {
                Picker("WebP effort", selection: $model.settings.quality.effort) {
                    Text("Fast").tag(2)
                    Text("Balanced").tag(4)
                    Text("Smallest (slow)").tag(6)
                }
            }
            if effectiveFormat == .png || effectiveFormat == nil {
                Toggle("Optimize PNG palette when lossless", isOn: $model.settings.quality.optimizePNGPalette)
            }
            if let format = effectiveFormat {
                Text(format.qualityExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let risk = QualitySettings.artifactRisk(quality: model.settings.quality.quality, format: format, lossless: model.settings.quality.lossless).message {
                    InlineNote(text: risk, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }
            }
            if let size = model.preview.estimatedSize, let item = model.selectedItem, let analysis = item.analysis {
                let percent = analysis.fileSize > 0 ? (1 - Double(size) / Double(analysis.fileSize)) * 100 : 0
                HStack(spacing: 6) {
                    Text("Estimated output for \(item.name):")
                    Text(model.format(size)).monospacedDigit()
                    ReductionText(percent: percent)
                    if model.preview.isRendering { ProgressView().controlSize(.mini) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            } else if model.preview.isRendering {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Estimating output size…").font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Quality")
        } footer: {
            Text(QualitySettings.crossFormatNote)
        }
        .disabled(model.settings.auto.isEnabled)
    }
}

// MARK: - Metadata

struct MetadataSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            Picker("Metadata", selection: $model.settings.metadata.policy) {
                ForEach(MetadataPolicy.allCases) { policy in Text(policy.displayName).tag(policy) }
            }
            Text(model.settings.metadata.policy.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Convert colors to sRGB", isOn: $model.settings.metadata.convertToSRGB)
                .disabled(model.settings.metadata.policy == .removeAll)
            Text(MetadataSettings.colorExplanation)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.settings.metadata.policy == .keepAll {
                Toggle("Remove GPS location", isOn: $model.settings.metadata.stripGPS)
                if !model.settings.metadata.stripGPS {
                    InlineNote(text: "Location data will be published with the images.", systemImage: "location.fill", tint: .orange)
                }
            }
        } header: {
            Text("Metadata and color")
        }
    }
}

// MARK: - Output

struct OutputSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Section {
            Picker("Save to", selection: $model.settings.output.destination) {
                ForEach(OutputSettings.Destination.allCases) { destination in
                    Text(destination.displayName).tag(destination)
                }
            }
            switch model.settings.output.destination {
            case .optimizedSubfolder:
                TextField("Subfolder name", text: $model.settings.output.subfolderName)
                Toggle("Preserve folder structure of imported folders", isOn: $model.settings.output.preserveFolderStructure)
            case .customFolder:
                LabeledContent("Folder") {
                    HStack {
                        Text(model.settings.output.customFolderPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "None chosen")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(model.settings.output.customFolderPath == nil ? .secondary : .primary)
                        Button("Choose…") { model.chooseCustomOutputFolder() }
                            .controlSize(.small)
                    }
                }
                Toggle("Preserve folder structure of imported folders", isOn: $model.settings.output.preserveFolderStructure)
            case .besideOriginals:
                EmptyView()
            case .replaceOriginals:
                InlineNote(text: "Originals are moved to the Trash and replaced after you confirm. Files that would get bigger are left untouched.", systemImage: "exclamationmark.triangle.fill", tint: .orange)
            }
            if model.settings.output.destination != .replaceOriginals {
                Picker("File name suffix", selection: $model.settings.output.suffix) {
                    ForEach(OutputSettings.Suffix.allCases) { suffix in Text(suffix.displayName).tag(suffix) }
                }
                if model.settings.output.suffix == .custom {
                    TextField("Custom suffix", text: $model.settings.output.customSuffix, prompt: Text("-small"))
                }
                Picker("If the file exists", selection: $model.settings.output.conflictPolicy) {
                    ForEach(OutputSettings.ConflictPolicy.allCases) { policy in Text(policy.displayName).tag(policy) }
                }
            }
            Toggle("Keep the original if the result would be larger", isOn: $model.settings.output.keepOriginalIfLarger)
            if let item = model.selectedItem, let example = exampleName(for: item) {
                Text("Example: \(example)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } header: {
            Text("Output")
        } footer: {
            Text("Source files are never overwritten unless you choose “Replace the originals”. Name clashes inside a batch are resolved automatically.")
        }
    }

    private func exampleName(for item: QueueItem) -> String? {
        guard let job = item.job else { return nil }
        let plan = OptimizationPipeline.plan(for: job, context: PipelineContext(settings: model.settings, capabilities: model.capabilities))
        let namer = OutputNamer(settings: model.settings.resolvedForProcessing.output, customFolder: model.settings.output.customFolderPath.map { URL(fileURLWithPath: $0) })
        guard let url = try? namer.proposedURL(for: item.url, importRoot: item.importRoot, format: plan.outputFormat) else { return nil }
        return (url.path as NSString).abbreviatingWithTildeInPath
    }
}
