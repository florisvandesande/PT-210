#if targetEnvironment(macCatalyst)
import PT210PrintCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("PT-210 Print").font(.title)
            Text(model.bluetooth.connectedPrinterName ?? "No PT-210 connected")
            TextField("Text to print", text: $model.text)
                .frame(minHeight: 44)
            HStack(spacing: 12) {
                Button("Search") { model.bluetooth.startScan() }
                Button("Print") { model.printCurrent() }
                Button("Preview") { model.makePreview() }
            }
            if model.isWorking {
                Text("Working…")
            }
            if let message = model.errorMessage {
                Text(message)
            }
            if let message = model.successMessage {
                Text(message)
            }
            if !model.bluetooth.discoveredPrinters.isEmpty {
                Text("Printers")
                ForEach(model.bluetooth.discoveredPrinters.prefix(3)) { printer in
                    Button("\(printer.name)  \(printer.rssi) dBm") {
                        model.run { try await model.bluetooth.connect(to: printer.id) }
                    }
                }
            }
        }
        .padding(24)
    }
}
#else
import PT210PrintCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var showsPrinterSheet = false
    @State private var showsSettings = false
#if !targetEnvironment(macCatalyst)
    @State private var selectedPhoto: PhotosPickerItem?
#endif
    @State private var showsFileImporter = false
    @State private var pendingJobForDeletion: PrintJob?

    var body: some View {
        NavigationView {
            Form {
                preparedJobsSection
                printerSection
                contentSection
                printOptionsSection
                printActionsSection
                messageSections
            }
            .navigationTitle("PT-210 Print")
            .toolbar {
                ToolbarItem(placement: .automatic) {
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
                NavigationView {
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
            .onChange(of: selectedPhoto) { item in
                guard let item else { return }
                model.run {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw PrintError.unsupportedContent
                    }
                    try await model.importImage(data: data, suggestedName: "photo.heic")
                }
            }
#endif
            .onChange(of: model.printerSettings) { _ in model.markSettingsCustom() }
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

    @ViewBuilder
    private var preparedJobsSection: some View {
        if !model.pendingJobs.isEmpty {
            Section("Prepared jobs") {
                ForEach(model.pendingJobs) { job in
                    Button {
                        model.openPendingJob(job)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pendingTitle(job))
                                Text(Self.jobDateFormatter.string(from: job.createdAt))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if model.activePendingJob?.id == job.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
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
    }

    private var printerSection: some View {
        Section {
            Button { showsPrinterSheet = true } label: {
                LabeledContent("Printer", value: printerStatus)
            }
            .accessibilityHint("Find or manage the PT-210 printer")
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        Section("Content") {
            Picker("Format", selection: $model.editorMode) {
                ForEach(AppModel.EditorMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.editorMode) { mode in model.applyRecommendedProfile(for: mode) }
            if model.editorMode == .image {
                imageEditor
            } else {
                textEditor
            }
        }
    }

    @ViewBuilder
    private var imageEditor: some View {
        if let url = model.selectedImageURL, let image = UIImage(contentsOfFile: url.path()) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 260)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Selected image")
            Text(model.selectedImageName ?? "Selected image")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "photo").font(.title)
                Text("Choose an image")
                Text("JPEG, PNG, HEIC, and HEIF are supported.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
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
    }

    @ViewBuilder
    private var textEditor: some View {
        TextEditor(text: $model.text)
            .frame(minHeight: 220)
            .font(.system(size: 17, design: model.editorMode == .html ? .monospaced : .default))
            .accessibilityLabel("Print content")
        if model.editorMode == .html {
            TextField("CSS", text: $model.css)
                .font(.system(size: 17, design: .monospaced))
        }
    }

    private var printOptionsSection: some View {
        Section("Print options") {
            Stepper("Copies: \(model.copies)", value: $model.copies, in: 1...20)
            Stepper("Feed lines: \(model.feedLines)", value: $model.feedLines, in: 0...20)
        }
    }

    @ViewBuilder
    private var printActionsSection: some View {
        Section {
            Button("Thermal preview", systemImage: "eye", action: model.makePreview)
                .disabled(model.isWorking || !model.canPrint)
            Button(action: model.printCurrent) {
                HStack {
                    Spacer()
                    if model.isWorking { ProgressView().padding(.trailing, 8) }
                    Text("Print").fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(model.isWorking || !model.canPrint)
            if model.isWorking {
                Button("Cancel current operation", role: .destructive, action: model.cancelCurrentOperation)
            }
        }
    }

    @ViewBuilder
    private var messageSections: some View {
        if let message = model.errorMessage {
            Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundColor(.red) }
        }
        if let message = model.successMessage {
            Section { Label(message, systemImage: "checkmark.circle.fill").foregroundColor(.green) }
        }
    }

    private func imageAdjustment(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading) {
            LabeledContent(title, value: formattedNumber(value.wrappedValue, fractionDigits: 2))
            Slider(value: value, in: range, step: 0.05)
        }
    }

    private var printerStatus: String {
        switch model.bluetooth.state {
        case .ready: model.bluetooth.connectedPrinterName ?? pt210Localized("Ready")
        case .scanning: pt210Localized("Searching…")
        case .connecting: pt210Localized("Connecting…")
        case .bluetoothUnavailable: pt210Localized("Bluetooth unavailable")
        default: pt210Localized("Not connected")
        }
    }

    private func pendingTitle(_ job: PrintJob) -> String {
        switch job.content {
        case .plainText: pt210Localized("Shared text")
        case .markdown: pt210Localized("Shared Markdown")
        case .html: pt210Localized("Shared HTML")
        case .image: pt210Localized("Shared image")
        }
    }
}

private extension ContentView {
    static let jobDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private func formattedNumber(_ value: Double, fractionDigits: Int) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = fractionDigits
    formatter.maximumFractionDigits = fractionDigits
    return formatter.string(from: NSNumber(value: value)) ?? String(value)
}

private extension Optional where Wrapped == URL {
    func okOrUnsupported() throws -> URL {
        guard let self else { throw PrintError.unsupportedContent }
        return self
    }
}

private struct PrinterView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
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
        case .ready: pt210Localized("Ready to print")
        case .connected: pt210Localized("Discovering printer services…")
        case .connecting: pt210Localized("Connecting…")
        case .scanning: pt210Localized("Searching…")
        case .bluetoothUnavailable: pt210Localized("Bluetooth unavailable")
        case .error(let message): message
        default: pt210Localized("Not connected")
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Quality") {
                    Picker("Preset", selection: $model.qualityPreset) {
                        ForEach(AppModel.QualityPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .onChange(of: model.qualityPreset) { preset in model.applyPreset(preset) }
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
                    LabeledContent("Last duration", value: model.executor.diagnostics.lastDurationSeconds.map { "\(formattedNumber($0, fractionDigits: 2)) s" } ?? "—")
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
            .onChange(of: model.printerSettings) { _ in model.markSettingsCustom() }
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
            LabeledContent(title, value: formattedNumber(value.wrappedValue, fractionDigits: step < 1 ? 2 : 0))
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
    @ObservedObject var model: AppModel
    @State private var page = 0

    var body: some View {
        NavigationView {
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
#endif
