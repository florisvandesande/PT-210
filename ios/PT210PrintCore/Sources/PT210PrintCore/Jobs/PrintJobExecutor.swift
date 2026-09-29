import CoreGraphics
import Foundation
import ImageIO

@MainActor
public final class PrintJobExecutor {
    public private(set) var state: PrintJobState = .idle
    public private(set) var diagnostics = PrintExecutionDiagnostics()
    private let bluetooth: PT210BluetoothManager
    private let settingsStore: SharedSettingsStore

    public init(bluetooth: PT210BluetoothManager, settingsStore: SharedSettingsStore = SharedSettingsStore()) {
        self.bluetooth = bluetooth
        self.settingsStore = settingsStore
    }

    public func preview(_ job: PrintJob, assetURL: URL? = nil) async throws -> MonochromeBitmap {
        state = .rendering
        let storedSettings = try await settingsStore.load()
        let settings = effectiveSettings(for: job, storedSettings: storedSettings)
        let image = try await render(job.content, settings: settings.render, assetURL: assetURL)
        return try ImageProcessor.monochrome(image: image, settings: settings)
    }

    public func execute(_ job: PrintJob, assetURL: URL? = nil) async throws {
        let start = ContinuousClock.now
        do {
            state = .preparing
            let storedSettings = try await settingsStore.load()
            let settings = effectiveSettings(for: job, storedSettings: storedSettings)
            let image = try await render(job.content, settings: settings.render, assetURL: assetURL)
            let bitmap = try ImageProcessor.monochrome(image: image, settings: settings)
            let strips = try ESCPOSRasterEncoder.makeStrips(
                bitmap: bitmap,
                rowsPerStrip: settings.transport.rasterStripHeight
            )
            let feedStrips = try ESCPOSRasterEncoder.makeFeedStrips(
                widthBytes: bitmap.bytesPerRow,
                lines: job.feedLinesAfter,
                rowsPerStrip: settings.transport.rasterStripHeight
            )
            state = .connecting
            try await ensurePrinterConnection()
            state = .configuringPrinter
            try await bluetooth.send(ESCPos.initialize, pacingMilliseconds: settings.transport.blePacingMilliseconds)
            try await bluetooth.send(try ESCPos.energy(settings.quality), pacingMilliseconds: settings.transport.blePacingMilliseconds)

            for copy in 0..<job.copies {
                for (index, strip) in strips.enumerated() {
                    try Task.checkCancellation()
                    let completed = Double(copy * strips.count + index) / Double(job.copies * strips.count)
                    state = .sending(progress: completed)
                    try await bluetooth.send(strip, pacingMilliseconds: settings.transport.blePacingMilliseconds)
                    try await Task.sleep(for: .milliseconds(settings.transport.postStripDelayMilliseconds))
                }
                for strip in feedStrips {
                    try await bluetooth.send(strip, pacingMilliseconds: settings.transport.blePacingMilliseconds)
                    try await Task.sleep(for: .milliseconds(settings.transport.postStripDelayMilliseconds))
                }
            }
            diagnostics.lastJobBytes = (strips.reduce(0) { $0 + $1.count }
                + feedStrips.reduce(0) { $0 + $1.count }) * job.copies
            diagnostics.lastDurationSeconds = start.duration(to: .now).seconds
            diagnostics.lastError = nil
            state = .completed
        } catch is CancellationError {
            state = .cancelled
            throw PrintError.cancelled
        } catch {
            diagnostics.lastError = error.localizedDescription
            diagnostics.lastDurationSeconds = start.duration(to: .now).seconds
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    private func effectiveSettings(
        for job: PrintJob,
        storedSettings: PrinterSettings
    ) -> PrinterSettings {
        var selectedSettings = storedSettings
        switch PrintQualityPresetID(rawValue: job.qualityPresetID ?? "") {
        case .text:
            selectedSettings.quality = PrinterSettings.highQualityText.quality
            selectedSettings.transport = PrinterSettings.highQualityText.transport
        case .imageHighQuality:
            selectedSettings.quality = PrinterSettings.highQuality.quality
            selectedSettings.transport = PrinterSettings.highQuality.transport
            selectedSettings.render.horizontalMargin = PrinterSettings.highQuality.render.horizontalMargin
        case .fast:
            selectedSettings.quality = PrinterSettings.fast.quality
            selectedSettings.transport = PrinterSettings.fast.transport
        case .balanced:
            selectedSettings.quality = PrinterSettings.balanced.quality
            selectedSettings.transport = PrinterSettings.balanced.transport
        case .highQuality:
            selectedSettings.quality = PrinterSettings.highQuality.quality
            selectedSettings.transport = PrinterSettings.highQuality.transport
            selectedSettings.render.horizontalMargin = PrinterSettings.highQuality.render.horizontalMargin
        case .custom, .none:
            break
        }

        return selectedSettings
    }

    public func executeCalibration(
        imageURL: URL,
        variants: [CalibrationVariant] = CalibrationVariant.screeningRound
    ) async throws {
        do {
            guard !variants.isEmpty else { throw PrintError.invalidSettings }
            state = .preparing
            let baseSettings = try await settingsStore.load()
            guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1_536
                  ] as CFDictionary) else { throw PrintError.renderFailed }

            state = .connecting
            try await ensurePrinterConnection()
            state = .configuringPrinter
            try await bluetooth.send(ESCPos.initialize, pacingMilliseconds: baseSettings.transport.blePacingMilliseconds)
            try await bluetooth.send(try ESCPos.energy(baseSettings.quality), pacingMilliseconds: baseSettings.transport.blePacingMilliseconds)

            for (variantIndex, variant) in variants.enumerated() {
                try Task.checkCancellation()
                var settings = baseSettings
                // Calibration photos use the full 384-dot print head. Any
                // remaining asymmetry is the physical head position on the
                // wider paper, not an unused section of the raster.
                settings.render.horizontalMargin = 0
                settings.quality.dithering = variant.dithering
                settings.quality.threshold = variant.threshold
                settings.quality.brightness = variant.brightness
                settings.quality.contrast = variant.contrast
                settings.quality.gamma = variant.gamma
                settings.quality.sharpness = variant.sharpness
                settings.quality.localContrast = variant.localContrast
                if let value = variant.rasterStripHeight { settings.transport.rasterStripHeight = value }
                if let value = variant.blePacingMilliseconds { settings.transport.blePacingMilliseconds = value }
                if let value = variant.postStripDelayMilliseconds { settings.transport.postStripDelayMilliseconds = value }
                if let value = variant.heatingTime { settings.quality.heatingTime = value }
                if let value = variant.heatingInterval { settings.quality.heatingInterval = value }
                try await bluetooth.send(
                    try ESCPos.energy(settings.quality),
                    pacingMilliseconds: settings.transport.blePacingMilliseconds
                )

                let imageBitmap = try ImageProcessor.monochrome(
                    image: image,
                    settings: settings,
                    calibrationProcessing: variant.imageProcessing
                )
                var labelRender = settings.render
                labelRender.textFontSize = 14
                labelRender.lineSpacing = 2
                labelRender.topMargin = 6
                labelRender.bottomMargin = 6
                let fullLabel = variant.label + "\nHeat D:\(settings.quality.maxHeatingDots) T:\(settings.quality.heatingTime) I:\(settings.quality.heatingInterval)  BLE:\(settings.transport.blePacingMilliseconds)ms Strip:\(settings.transport.rasterStripHeight) Delay:\(settings.transport.postStripDelayMilliseconds)"
                let labelImage = try TextRenderer.render(.plainText(fullLabel), settings: labelRender)
                let labelBitmap = try ImageProcessor.monochrome(image: labelImage, settings: settings)
                let bitmaps = [imageBitmap, labelBitmap]

                for bitmap in bitmaps {
                    let strips = try ESCPOSRasterEncoder.makeStrips(
                        bitmap: bitmap,
                        rowsPerStrip: settings.transport.rasterStripHeight
                    )
                    for strip in strips {
                        try Task.checkCancellation()
                        try await bluetooth.send(strip, pacingMilliseconds: settings.transport.blePacingMilliseconds)
                        try await Task.sleep(for: .milliseconds(settings.transport.postStripDelayMilliseconds))
                    }
                }
                let feed = try ESCPOSRasterEncoder.makeFeedStrips(
                    widthBytes: imageBitmap.bytesPerRow,
                    lines: 2,
                    rowsPerStrip: settings.transport.rasterStripHeight
                )
                for strip in feed {
                    try await bluetooth.send(strip, pacingMilliseconds: settings.transport.blePacingMilliseconds)
                }
                state = .sending(progress: Double(variantIndex + 1) / Double(variants.count))
                // Give the small thermal head time to cool between full-width photos.
                try await Task.sleep(for: .milliseconds(800))
            }
            state = .completed
        } catch is CancellationError {
            state = .cancelled
            throw PrintError.cancelled
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    private func render(_ content: PrintContent, settings: RenderSettings, assetURL: URL?) async throws -> CGImage {
        switch content {
        case .plainText, .markdown:
            return try TextRenderer.render(content, settings: settings)
        case .html(let html, let css):
            return try await HTMLRenderer().render(
                html: html,
                css: css,
                width: settings.pageWidthPixels - settings.horizontalMargin * 2
            )
        case .image:
            guard let assetURL,
                  let source = CGImageSourceCreateWithURL(assetURL as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1_536
                  ] as CFDictionary) else { throw PrintError.renderFailed }
            return image
        }
    }

    private func ensurePrinterConnection() async throws {
        guard bluetooth.state != .ready else { return }
        do {
            try await bluetooth.reconnectSavedPrinter()
        } catch {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(500))
            try await bluetooth.reconnectSavedPrinter()
        }
    }
}

private extension Duration {
    var seconds: Double {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
