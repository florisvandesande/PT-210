import PT210PrintCore
#if !targetEnvironment(macCatalyst)
import PhotosUI
#endif
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var showsPrinterSheet = false
    @State private var showsSettings = false
#if !targetEnvironment(macCatalyst)
    @State private var selectedPhoto: PhotosPickerItem?
#endif
    @State private var showsFileImporter = false
    @State private var pendingJobForDeletion: PrintJob?

    var body: some View {
        NavigationStack {
            Form {
                if !model.pendingJobs.isEmpty {
                    Section("Prepared jobs") {
                        ForEach(model.pendingJobs) { job in
                            Button {
                                model.openPendingJob(job)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(pendingTitle(job))
                                        Text(job.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if model.activePendingJob?.id == job.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.green)
                                            .accessibilityLabel("Selected")
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete job", systemImage: "trash", role: .destructive) {
                                    pendingJobForDeletion = job
                                }
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) { model.deletePending(job) }
                            }
                        }
                    }
                }
                Section {
                    Button {
                        showsPrinterSheet = true
                    } label: {
                        LabeledContent("Printer", value: printerStatus)
                    }
                    .accessibilityHint("Find or manage the PT-210 printer")
                }

                Section("Content") {
                    Picker("Format", selection: $model.editorMode) {
                        ForEach(AppModel.EditorMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.editorMode) { _, mode in model.applyRecommendedProfile(for: mode) }
                    if model.editorMode == .image {
                        if let url = model.selectedImageURL,
                           let image = UIImage(contentsOfFile: url.path()) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 260)
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel("Selected image")
                            Text(model.selectedImageName ?? "Selected image")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ContentUnavailableView(
                                "Choose an image",
                                systemImage: "photo",
                                description: Text("JPEG, PNG, HEIC, and HEIF are supported.")
                            )
                            .frame(minHeight: 180)
                        }
                        HStack {
#if !targetEnvironment(macCatalyst)
                            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                Label("Photos", systemImage: "photo.on.rectangle")
                            }
#endif
                            Spacer()
                            Button("Files", systemImage: "folder") { showsFileImporter = true }
                        }
                        Picker("Scaling", selection: $model.printerSettings.render.imageScaling) {
                            Text("Fit width").tag(ImageScalingMode.fitWidth)
                            Text("Actual size").tag(ImageScalingMode.actualSize)
                            Text("Center").tag(ImageScalingMode.center)
                            Text("Square crop").tag(ImageScalingMode.cropToWidth)
                        }
                        DisclosureGroup("Image adjustments") {
                            imageAdjustment("Brightness", value: $model.printerSettings.quality.brightness, range: -1...1)
                            imageAdjustment("Contrast", value: $model.printerSettings.quality.contrast, range: 0.5...2.5)
                            imageAdjustment("Gamma", value: $model.printerSettings.quality.gamma, range: 0.2...3)
                            imageAdjustment("Threshold", value: $model.printerSettings.quality.threshold, range: 0.1...0.9)
                            Picker("Dithering", selection: $model.printerSettings.quality.dithering) {
                                Text("Threshold").tag(DitheringAlgorithm.threshold)
                                Text("Floyd–Steinberg").tag(DitheringAlgorithm.floydSteinberg)
                                Text("Atkinson").tag(DitheringAlgorithm.atkinson)
                                Text("Bayer 4×4").tag(DitheringAlgorithm.bayer4x4)
                            }
                            Toggle("Invert black and white", isOn: $model.printerSettings.quality.invert)
                        }
                    } else {
                        TextEditor(text: $model.text)
                            .frame(minHeight: 220)
                            .font(.body.monospaced(model.editorMode == .html))
                            .accessibilityLabel("Print content")
                        if model.editorMode == .html {
                            TextField("CSS", text: $model.css, axis: .vertical)
                                .font(.body.monospaced())
                        }
                    }
                }

                Section("Print options") {
                    Stepper("Copies: \(model.copies)", value: $model.copies, in: 1...20)
                    Stepper("Feed lines: \(model.feedLines)", value: $model.feedLines, in: 0...20)
                }

                Section {
                    Button("Thermal preview", systemImage: "eye", action: model.makePreview)
                        .disabled(model.isWorking || !model.canPrint)
                    Button(action: model.printCurrent) {
                        HStack {
                            Spacer()
                            if model.isWorking { ProgressView().padding(.trailing, 8) }
                            Text("Print")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(model.isWorking || !model.canPrint)
                    if model.isWorking {
                        Button("Cancel current operation", role: .destructive, action: model.cancelCurrentOperation)
                    }
                }

                if let message = model.errorMessage {
                    Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
                if let message = model.successMessage {
                    Section { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            .navigationTitle("PT-210 Print")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") { showsSettings = true }
                }
            }
            .sheet(isPresented: $showsPrinterSheet) { PrinterView(model: model) }
            .sheet(isPresented: $showsSettings) { SettingsView(model: model) }
            .fullScreenCover(isPresented: $model.showsOnboarding) {
                OnboardingView(model: model)
                    .interactiveDismissDisabled()
            }
            .sheet(isPresented: $model.showsPreview) {
                NavigationStack {
                    ScrollView {
                        if let preview = model.thermalPreview {
                            Image(uiImage: preview)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .padding()
                                .accessibilityLabel("Thermal print preview")
                        }
                    }
                    .background(Color(uiColor: .systemGroupedBackground))
                    .navigationTitle("Thermal preview")
                    .toolbar { Button("Done") { model.showsPreview = false } }
                }
            }
            .fileImporter(
                isPresented: $showsFileImporter,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                model.run {
                    let url = try result.get().first.okOrUnsupported()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    try await model.importImage(data: Data(contentsOf: url), suggestedName: url.lastPathComponent)
                }
            }
#if !targetEnvironment(macCatalyst)
            .onChange(of: selectedPhoto) { _, item in
                guard let item else { return }
                model.run {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw PrintError.unsupportedContent
                    }
                    try await model.importImage(data: data, suggestedName: "photo.heic")
                }
            }
#endif
            .onChange(of: model.printerSettings) { _, _ in model.markSettingsCustom() }
            .confirmationDialog(
                "Delete prepared job?",
                isPresented: Binding(
                    get: { pendingJobForDeletion != nil },
                    set: { if !$0 { pendingJobForDeletion = nil } }
                ),
                presenting: pendingJobForDeletion
            ) { job in
                Button("Delete prepared job", role: .destructive) {
                    model.deletePending(job)
                    pendingJobForDeletion = nil
                }
                Button("Cancel", role: .cancel) { pendingJobForDeletion = nil }
            } message: { _ in
                Text("This removes the prepared job from this iPhone. This cannot be undone.")
            }
        }
    }

    private func imageAdjustment(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: value.wrappedValue.formatted(.number.precision(.fractionLength(2))))
            Slider(value: value, in: range, step: 0.05)
        }
    }

    private var printerStatus: String {
        switch model.bluetooth.state {
        case .ready: model.bluetooth.connectedPrinterName ?? String(localized: "Ready")
        case .scanning: String(localized: "Searching…")
        case .connecting: String(localized: "Connecting…")
        case .bluetoothUnavailable: String(localized: "Bluetooth unavailable")
        default: String(localized: "Not connected")
        }
    }

    private func pendingTitle(_ job: PrintJob) -> String {
        switch job.content {
        case .plainText: String(localized: "Shared text")
        case .markdown: String(localized: "Shared Markdown")
        case .html: String(localized: "Shared HTML")
        case .image: String(localized: "Shared image")
        }
    }
}

private extension Optional where Wrapped == URL {
    func okOrUnsupported() throws -> URL {
        guard let self else { throw PrintError.unsupportedContent }
        return self
    }
}

private struct PrinterView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    Text(statusText)
                    if model.bluetooth.state == .ready {
                        Button("Disconnect") { model.bluetooth.disconnect() }
                        Button("Forget printer", role: .destructive) {
                            model.run { try await model.bluetooth.forgetPrinter() }
                        }
                    } else {
                        Button("Reconnect saved printer", action: model.reconnect)
                        Button("Search for PT-210") { model.bluetooth.startScan() }
                    }
                }
                if !model.bluetooth.discoveredPrinters.isEmpty {
                    Section("Nearby printers") {
                        ForEach(model.bluetooth.discoveredPrinters) { printer in
                            Button {
                                model.run { try await model.bluetooth.connect(to: printer.id) }
                            } label: {
                                LabeledContent(printer.name, value: "\(printer.rssi) dBm")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Printer")
            .toolbar { Button("Done") { dismiss() } }
            .onDisappear { model.bluetooth.stopScan() }
        }
    }

    private var statusText: String {
        switch model.bluetooth.state {
        case .ready: String(localized: "Ready to print")
        case .connected: String(localized: "Discovering printer services…")
        case .connecting: String(localized: "Connecting…")
        case .scanning: String(localized: "Searching…")
        case .bluetoothUnavailable: String(localized: "Bluetooth unavailable")
        case .error(let message): message
        default: String(localized: "Not connected")
        }
    }
}

private struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Quality") {
                    Picker("Preset", selection: $model.qualityPreset) {
                        ForEach(AppModel.QualityPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .onChange(of: model.qualityPreset) { _, preset in model.applyPreset(preset) }
                }

                Section("Image") {
                    settingSlider(
                        "Brightness",
                        value: $model.printerSettings.quality.brightness,
                        range: -1...1,
                        step: 0.05
                    )
                    settingSlider(
                        "Contrast",
                        value: $model.printerSettings.quality.contrast,
                        range: 0.5...2.5,
                        step: 0.05
                    )
                    settingSlider(
                        "Gamma",
                        value: $model.printerSettings.quality.gamma,
                        range: 0.2...3,
                        step: 0.05
                    )
                    settingSlider(
                        "Threshold",
                        value: $model.printerSettings.quality.threshold,
                        range: 0.1...0.9,
                        step: 0.05
                    )
                    Picker("Dithering", selection: $model.printerSettings.quality.dithering) {
                        Text("Threshold").tag(DitheringAlgorithm.threshold)
                        Text("Floyd–Steinberg").tag(DitheringAlgorithm.floydSteinberg)
                        Text("Atkinson").tag(DitheringAlgorithm.atkinson)
                        Text("Bayer 4×4").tag(DitheringAlgorithm.bayer4x4)
                    }
                    Toggle("Invert black and white", isOn: $model.printerSettings.quality.invert)
                }

                Section("Layout") {
                    settingSlider(
                        "Horizontal margin",
                        value: intBinding(\.render.horizontalMargin),
                        range: 0...48,
                        step: 1
                    )
                    settingSlider(
                        "Text size",
                        value: $model.printerSettings.render.textFontSize,
                        range: 12...48,
                        step: 1
                    )
                    settingSlider(
                        "Line spacing",
                        value: $model.printerSettings.render.lineSpacing,
                        range: 0...20,
                        step: 1
                    )
                }

                DisclosureGroup("Advanced") {
                    settingSlider(
                        "Heating dots",
                        value: byteBinding(\.quality.maxHeatingDots),
                        range: 1...7,
                        step: 1
                    )
                    settingSlider(
                        "Heating time",
                        value: byteBinding(\.quality.heatingTime),
                        range: 40...180,
                        step: 5
                    )
                    settingSlider(
                        "Heating interval",
                        value: byteBinding(\.quality.heatingInterval),
                        range: 1...10,
                        step: 1
                    )
                    settingSlider(
                        "BLE pacing (ms)",
                        value: intBinding(\.transport.blePacingMilliseconds),
                        range: 10...100,
                        step: 5
                    )
                    settingSlider(
                        "Strip height",
                        value: intBinding(\.transport.rasterStripHeight),
                        range: 8...64,
                        step: 8
                    )
                    settingSlider(
                        "Post-strip delay (ms)",
                        value: intBinding(\.transport.postStripDelayMilliseconds),
                        range: 20...150,
                        step: 5
                    )
                }
                Section("Diagnostics") {
                    LabeledContent("Peripheral", value: model.bluetooth.diagnostics.peripheralIdentifier?.uuidString ?? "—")
                    LabeledContent("Service", value: model.bluetooth.diagnostics.serviceUUID ?? "—")
                    LabeledContent("Write characteristic", value: model.bluetooth.diagnostics.writeUUID ?? "—")
                    LabeledContent("Notify characteristic", value: model.bluetooth.diagnostics.notifyUUID ?? "—")
                    LabeledContent("Write properties", value: model.bluetooth.diagnostics.writeProperties ?? "—")
                    LabeledContent("Maximum write length", value: model.bluetooth.diagnostics.maximumWriteLength.map(String.init) ?? "—")
                    LabeledContent("RSSI", value: model.bluetooth.diagnostics.rssi.map { "\($0) dBm" } ?? "—")
                    LabeledContent("Heating", value: "D:\(model.printerSettings.quality.maxHeatingDots) T:\(model.printerSettings.quality.heatingTime) I:\(model.printerSettings.quality.heatingInterval)")
                    LabeledContent("Transport", value: "\(model.printerSettings.transport.blePacingMilliseconds) ms / \(model.printerSettings.transport.rasterStripHeight) rows")
                    LabeledContent("Last job bytes", value: model.executor.diagnostics.lastJobBytes.map(String.init) ?? "—")
                    LabeledContent("Last duration", value: model.executor.diagnostics.lastDurationSeconds.map { "\($0.formatted(.number.precision(.fractionLength(2)))) s" } ?? "—")
                    LabeledContent("Last error", value: model.executor.diagnostics.lastError ?? "—")
                    Button("Print quality test page", systemImage: "doc.text.magnifyingglass", action: model.printTestPage)
                    Image("QualityTestImage")
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Squirrel image used for quality comparison")
                    Button(
                        "Print image quality comparison",
                        systemImage: "photo.badge.magnifyingglass",
                        action: model.printAdvancedImageQualityTest
                    )
                    Text("Prints the bundled squirrel photo three times: Lanczos-5 resampling, percentile contrast, and reproducible blue-noise dithering. Saved profiles are not changed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    Text("Printing stays on this iPhone. The app has no account, analytics, server, or cloud storage.")
                }
            }
            .navigationTitle("Settings")
            .onChange(of: model.printerSettings) { _, _ in model.markSettingsCustom() }
            .toolbar {
                Button("Save") {
                    model.saveSettings()
                    dismiss()
                }
            }
        }
    }

    private func settingSlider(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: value.wrappedValue.formatted(.number.precision(.fractionLength(step < 1 ? 2 : 0))))
            Slider(value: value, in: range, step: step)
        }
    }

    private func intBinding(_ keyPath: WritableKeyPath<PrinterSettings, Int>) -> Binding<Double> {
        Binding(
            get: { Double(model.printerSettings[keyPath: keyPath]) },
            set: { model.printerSettings[keyPath: keyPath] = Int($0.rounded()) }
        )
    }

    private func byteBinding(_ keyPath: WritableKeyPath<PrinterSettings, UInt8>) -> Binding<Double> {
        Binding(
            get: { Double(model.printerSettings[keyPath: keyPath]) },
            set: { model.printerSettings[keyPath: keyPath] = UInt8(clamping: Int($0.rounded())) }
        )
    }
}

private struct OnboardingView: View {
    @Bindable var model: AppModel
    @State private var page = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: page == 0 ? "printer.fill" : page == 1 ? "antenna.radiowaves.left.and.right" : "checkmark.seal.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(page == 0 ? "Welcome to PT-210 Print" : page == 1 ? "Connect your PT-210" : "Ready to print")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(page == 0
                     ? "Print text, Markdown, HTML, and photos privately over Bluetooth."
                     : page == 1
                     ? "Turn on the printer, then search and select the strongest PT-210 signal. The app remembers it for next time."
                     : "High quality J06 is the photo default. Text uses its own sharp monochrome profile.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                if page == 1 {
                    Button("Search for PT-210", systemImage: "magnifyingglass") { model.bluetooth.startScan() }
                        .buttonStyle(.borderedProminent)
                    ForEach(model.bluetooth.discoveredPrinters.prefix(3)) { printer in
                        Button("\(printer.name)  \(printer.rssi) dBm") {
                            model.run { try await model.bluetooth.connect(to: printer.id) }
                        }
                    }
                }
                Spacer()
                Button(page == 2 ? "Start printing" : "Continue") {
                    if page < 2 { page += 1 } else { model.completeOnboarding() }
                }
                .buttonStyle(.borderedProminent)
                if page == 1 {
                    Button("Continue without printer") { page = 2 }
                }
            }
            .padding(32)
        }
    }
}
