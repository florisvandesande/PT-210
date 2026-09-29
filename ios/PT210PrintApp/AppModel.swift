import Observation
import PT210PrintCore
import SwiftUI
import UIKit

@MainActor
@Observable
final class AppModel {
    enum QualityPreset: String, CaseIterable, Identifiable {
        case text
        case imageHighQuality
        case custom

        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .text: "Text"
            case .imageHighQuality: "Image (High quality)"
            case .custom: "Custom"
            }
        }
    }

    enum EditorMode: String, CaseIterable, Identifiable {
        case text
        case markdown
        case html
        case image

        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .text: "Plain text"
            case .markdown: "Markdown"
            case .html: "HTML"
            case .image: "Image"
            }
        }
    }

    let bluetooth = PT210BluetoothManager()
    @ObservationIgnored private(set) lazy var executor = PrintJobExecutor(bluetooth: bluetooth)
    @ObservationIgnored private let settingsStore = SharedSettingsStore()
    @ObservationIgnored private let jobStore: PrintJobStore?
    @ObservationIgnored private var currentTask: Task<Void, Never>?
    var editorMode: EditorMode = .text
    var text = String(localized: "Hello from PT-210 Print")
    var css = "h1 { text-align: center; }"
    var copies = 1
    var feedLines = 3
    var isWorking = false
    var errorMessage: String?
    var successMessage: String?
    var selectedImageURL: URL?
    var selectedImageName: String?
    var thermalPreview: UIImage?
    var showsPreview = false
    var printerSettings = PrinterSettings.highQualityText
    var qualityPreset: QualityPreset = .text
    var pendingJobs: [PrintJob] = []
    var activePendingJob: PrintJob?
    var showsOnboarding = !UserDefaults.standard.bool(forKey: "completed-onboarding-v1")

    init() {
        jobStore = try? PrintJobStore()
        Task { @MainActor in
            if let loaded = try? await settingsStore.load() {
                printerSettings = loaded
                markSettingsCustom()
                if qualityPreset != .custom { applyRecommendedProfile(for: editorMode) }
            }
            await reconnectSavedPrinterOnLaunch()
            await refreshPendingJobs()
            try? await jobStore?.cleanup()
        }
    }

    var job: PrintJob {
        let content: PrintContent = switch editorMode {
        case .text: .plainText(text)
        case .markdown: .markdown(text)
        case .html: .html(html: text, css: css)
        case .image:
            .image(StoredImageReference(filename: selectedImageName ?? "selected-image"))
        }
        return PrintJob(
            content: content,
            qualityPresetID: qualityPreset.rawValue,
            copies: copies,
            feedLinesAfter: feedLines,
            source: .mainApp
        )
    }

    func reconnect() {
        run { try await self.bluetooth.reconnectSavedPrinter() }
    }

    func printCurrent() {
        run {
            try await self.settingsStore.save(self.printerSettings)
            do {
                try await self.executor.execute(self.job, assetURL: self.selectedImageURL)
            } catch {
                if let pending = self.activePendingJob, let store = self.jobStore {
                    try? await store.markFailed(pending)
                    self.activePendingJob = nil
                    self.pendingJobs = (try? await store.loadPending()) ?? []
                }
                throw error
            }
            if let pending = self.activePendingJob, let store = self.jobStore {
                try await store.markCompleted(pending)
                self.activePendingJob = nil
                self.pendingJobs = try await store.loadPending()
            }
            self.successMessage = String(localized: "Printed successfully")
        }
    }

    func openPendingJob(_ job: PrintJob) {
        errorMessage = nil
        successMessage = nil
        activePendingJob = job
        copies = job.copies
        feedLines = job.feedLinesAfter
        switch job.content {
        case .plainText(let value):
            editorMode = .text
            text = value
        case .markdown(let value):
            editorMode = .markdown
            text = value
        case .html(let html, let style):
            editorMode = .html
            text = html
            css = style ?? ""
        case .image(let reference):
            editorMode = .image
            selectedImageName = reference.filename
            selectedImageURL = nil
            applyPreset(.imageHighQuality)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let url = await self.jobStore?.assetURL(for: reference)
                guard self.activePendingJob?.id == job.id else { return }
                guard let url, FileManager.default.fileExists(atPath: url.path) else {
                    self.errorMessage = String(localized: "The prepared image is missing. Delete this job and prepare it again.")
                    return
                }
                self.selectedImageURL = url
                self.successMessage = String(localized: "Prepared job opened")
            }
        }
        thermalPreview = nil
        if case .image = job.content {
            // The image asset is resolved asynchronously above.
        } else {
            successMessage = String(localized: "Prepared job opened")
        }
    }

    func refreshPendingJobs() async {
        pendingJobs = (try? await jobStore?.loadPending()) ?? []
    }

    var canPrint: Bool {
        if editorMode == .image { return selectedImageURL != nil }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func importImage(data: Data, suggestedName: String?) async throws {
        guard !data.isEmpty else { throw PrintError.unsupportedContent }
        guard data.count <= 25 * 1_024 * 1_024 else { throw PrintError.inputTooLarge }
        let extensionName = URL(fileURLWithPath: suggestedName ?? "image.heic").pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("pt210-selected-\(UUID().uuidString)")
            .appendingPathExtension(extensionName.isEmpty ? "img" : extensionName)
        try data.write(to: destination, options: .atomic)
        if let oldURL = selectedImageURL { try? FileManager.default.removeItem(at: oldURL) }
        selectedImageURL = destination
        selectedImageName = suggestedName ?? destination.lastPathComponent
        thermalPreview = nil
        editorMode = .image
        applyPreset(.imageHighQuality)
        try await settingsStore.save(printerSettings)
    }

    func makePreview() {
        run {
            try await self.settingsStore.save(self.printerSettings)
            let bitmap = try await self.executor.preview(self.job, assetURL: self.selectedImageURL)
            self.thermalPreview = try Self.previewImage(from: bitmap)
            self.showsPreview = true
        }
    }

    func applyPreset(_ preset: QualityPreset) {
        qualityPreset = preset
        let presetSettings: PrinterSettings
        switch preset {
        case .text: presetSettings = .highQualityText
        case .imageHighQuality: presetSettings = .highQuality
        case .custom: return
        }
        printerSettings.quality = presetSettings.quality
        printerSettings.transport = presetSettings.transport
        if preset == .imageHighQuality {
            printerSettings.render.horizontalMargin = presetSettings.render.horizontalMargin
        }
    }

    func markSettingsCustom() {
        let candidates: [(QualityPreset, PrinterSettings)] = [
            (.text, .highQualityText),
            (.imageHighQuality, .highQuality)
        ]
        qualityPreset = candidates.first {
            printerSettings.quality == $0.1.quality
                && printerSettings.transport == $0.1.transport
        }?.0 ?? .custom
    }

    func applyRecommendedProfile(for mode: EditorMode) {
        applyPreset(mode == .image ? .imageHighQuality : .text)
    }

    func saveSettings() {
        run {
            try await self.settingsStore.save(self.printerSettings)
            self.successMessage = String(localized: "Settings saved")
            self.thermalPreview = nil
        }
    }

    func printTestPage() {
        let html = """
        <h1>PT-210 QUALITY TEST</h1>
        <p>ABCDEFGHIJKLMNOPQRSTUVWXYZ<br>
        abcdefghijklmnopqrstuvwxyz<br>
        0123456789</p>
        <p>á é ë ï ö ü &nbsp; € ✓ — –</p>
        <h2>Line accuracy</h2>
        <div class="line one"></div><div class="label">1 dot</div>
        <div class="line two"></div><div class="label">2 dots</div>
        <div class="line three"></div><div class="label">3 dots</div>
        <h2>Coverage</h2>
        <div class="coverage"><b>25%</b><span class="tone p25"></span></div>
        <div class="coverage"><b>50%</b><span class="tone p50"></span></div>
        <div class="coverage"><b>75%</b><span class="tone p75"></span></div>
        <div class="coverage"><b>100%</b><span class="tone p100"></span></div>
        """
        let css = """
        body{font-size:20px}h1{font-size:27px;margin:0 0 14px}h2{font-size:20px;margin:18px 0 8px}
        p{margin:0 0 14px}.line{width:100%;background:#000;margin-top:9px}.one{height:1px}.two{height:2px}.three{height:3px}
        .label{font-size:14px;margin:2px 0 5px}.coverage{display:flex;align-items:center;gap:8px;margin:6px 0}
        .coverage b{width:48px}.tone{display:block;width:260px;height:28px;border:1px solid #000}
        .p25{background:repeating-linear-gradient(90deg,#000 0 1px,#fff 1px 4px)}
        .p50{background:repeating-linear-gradient(90deg,#000 0 2px,#fff 2px 4px)}
        .p75{background:repeating-linear-gradient(90deg,#000 0 3px,#fff 3px 4px)}
        .p100{background:#000}
        """
        run {
            let job = PrintJob(content: .html(html: html, css: css), qualityPresetID: "text", source: .mainApp)
            try await self.executor.execute(job)
            self.successMessage = String(localized: "Test page printed")
        }
    }

    func printAdvancedImageQualityTest() {
        run {
            guard let image = UIImage(named: "QualityTestImage"),
                  let data = image.jpegData(compressionQuality: 1) else {
                throw PrintError.renderFailed
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("pt210-quality-test.jpg")
            try data.write(to: url, options: .atomic)
            defer { try? FileManager.default.removeItem(at: url) }
            try await self.executor.executeCalibration(
                imageURL: url,
                variants: CalibrationVariant.advancedQualityRound
            )
            self.successMessage = String(localized: "Image quality comparison printed")
        }
    }

    func deletePending(_ job: PrintJob) {
        run {
            try await self.jobStore?.delete(job)
            if self.activePendingJob?.id == job.id {
                self.activePendingJob = nil
            }
            self.pendingJobs = try await self.jobStore?.loadPending() ?? []
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "completed-onboarding-v1")
        showsOnboarding = false
    }

    func handleForeground() {
        Task { @MainActor in
            await reconnectSavedPrinterOnLaunch()
            await refreshPendingJobs()
        }
    }

    func cancelCurrentOperation() {
        currentTask?.cancel()
    }

    private func reconnectSavedPrinterOnLaunch() async {
        // CoreBluetooth publishes its initial state shortly after the manager
        // is created. Waiting avoids a false unavailable error at launch.
        for _ in 0..<30 where bluetooth.state == .unknown {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard bluetooth.state == .disconnected else { return }
        try? await bluetooth.reconnectSavedPrinter()
    }

    private static func previewImage(from bitmap: MonochromeBitmap) throws -> UIImage {
        var pixels = Data(repeating: 255, count: bitmap.width * bitmap.height)
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                let byte = bitmap.data[y * bitmap.bytesPerRow + x / 8]
                if byte & UInt8(0x80 >> (x % 8)) != 0 {
                    pixels[y * bitmap.width + x] = 0
                }
            }
        }
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(
                width: bitmap.width,
                height: bitmap.height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: bitmap.width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else { throw PrintError.renderFailed }
        return UIImage(cgImage: image)
    }

    func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        successMessage = nil
        currentTask = Task { @MainActor in
            defer {
                isWorking = false
                currentTask = nil
            }
            do { try await operation() } catch { errorMessage = error.localizedDescription }
        }
    }
}
