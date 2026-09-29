import CoreGraphics
import Foundation

public enum AppGroup {
    public static let identifier = "group.nl.florisvandesande.pt210print"
}

public enum PrintContent: Codable, Sendable, Equatable {
    case plainText(String)
    case markdown(String)
    case html(html: String, css: String?)
    case image(StoredImageReference)
}

public struct StoredImageReference: Codable, Sendable, Equatable {
    public let filename: String
    public let uti: String?

    public init(filename: String, uti: String? = nil) {
        self.filename = filename
        self.uti = uti
    }
}

public enum PrintJobSource: String, Codable, Sendable {
    case mainApp
    case shareExtension
    case shortcut
}

public enum PrintQualityPresetID: String, Codable, CaseIterable, Sendable {
    case text
    case imageHighQuality
    case custom
    // Kept for decoding existing prepared jobs created by earlier builds.
    case fast
    case balanced
    case highQuality
}

public struct PrintJob: Identifiable, Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public var content: PrintContent
    public var qualityPresetID: String?
    public var copies: Int
    public var feedLinesAfter: Int
    public var source: PrintJobSource

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        content: PrintContent,
        qualityPresetID: String? = "imageHighQuality",
        copies: Int = 1,
        feedLinesAfter: Int = 3,
        source: PrintJobSource
    ) {
        self.id = id
        self.createdAt = createdAt
        self.content = content
        self.qualityPresetID = qualityPresetID
        self.copies = max(1, min(copies, 20))
        self.feedLinesAfter = max(0, min(feedLinesAfter, 20))
        self.source = source
    }
}

public enum DitheringAlgorithm: String, Codable, CaseIterable, Sendable {
    case threshold
    case floydSteinberg
    case atkinson
    case bayer4x4
}

/// Experimental preprocessing used only by labelled diagnostic prints. These
/// cases never alter the saved or recommended printer profiles.
public enum CalibrationImageProcessing: String, Sendable, Equatable {
    case standard
    case lanczos5
    case percentileContrast
    case reproducibleBlueNoise
}

public struct CalibrationVariant: Identifiable, Sendable, Equatable {
    public let id: String
    public let dithering: DitheringAlgorithm
    public let threshold: Double
    public let brightness: Double
    public let contrast: Double
    public let gamma: Double
    public let rasterStripHeight: Int?
    public let blePacingMilliseconds: Int?
    public let postStripDelayMilliseconds: Int?
    public let heatingTime: UInt8?
    public let heatingInterval: UInt8?
    public let sharpness: Double
    public let localContrast: Double
    public let imageProcessing: CalibrationImageProcessing

    public init(
        id: String,
        dithering: DitheringAlgorithm,
        threshold: Double,
        brightness: Double = 0,
        contrast: Double = 1,
        gamma: Double = 1,
        rasterStripHeight: Int? = nil,
        blePacingMilliseconds: Int? = nil,
        postStripDelayMilliseconds: Int? = nil,
        heatingTime: UInt8? = nil,
        heatingInterval: UInt8? = nil,
        sharpness: Double = 0,
        localContrast: Double = 0,
        imageProcessing: CalibrationImageProcessing = .standard
    ) {
        self.id = id
        self.dithering = dithering
        self.threshold = threshold
        self.brightness = brightness
        self.contrast = contrast
        self.gamma = gamma
        self.rasterStripHeight = rasterStripHeight
        self.blePacingMilliseconds = blePacingMilliseconds
        self.postStripDelayMilliseconds = postStripDelayMilliseconds
        self.heatingTime = heatingTime
        self.heatingInterval = heatingInterval
        self.sharpness = sharpness
        self.localContrast = localContrast
        self.imageProcessing = imageProcessing
    }

    public var label: String {
        let method = switch dithering {
        case .threshold: "Threshold"
        case .bayer4x4: "Bayer4x4"
        case .atkinson: "Atkinson"
        case .floydSteinberg: "FloydSteinberg"
        }
        return "\(id) \(method) T:\(threshold.formatted(.number.precision(.fractionLength(2)))) B:\(brightness.formatted(.number.precision(.fractionLength(2)))) C:\(contrast.formatted(.number.precision(.fractionLength(2)))) G:\(gamma.formatted(.number.precision(.fractionLength(2)))) S:\(sharpness.formatted(.number.precision(.fractionLength(2)))) LC:\(localContrast.formatted(.number.precision(.fractionLength(2))))"
    }

    public static let screeningRound: [CalibrationVariant] = [
        .init(id: "A1", dithering: .threshold, threshold: 0.40),
        .init(id: "A2", dithering: .threshold, threshold: 0.50),
        .init(id: "A3", dithering: .threshold, threshold: 0.60),
        .init(id: "B1", dithering: .bayer4x4, threshold: 0.40),
        .init(id: "B2", dithering: .bayer4x4, threshold: 0.50),
        .init(id: "B3", dithering: .bayer4x4, threshold: 0.60),
        .init(id: "C1", dithering: .atkinson, threshold: 0.40),
        .init(id: "C2", dithering: .atkinson, threshold: 0.50),
        .init(id: "C3", dithering: .atkinson, threshold: 0.60),
        .init(id: "D1", dithering: .floydSteinberg, threshold: 0.40),
        .init(id: "D2", dithering: .floydSteinberg, threshold: 0.50),
        .init(id: "D3", dithering: .floydSteinberg, threshold: 0.60)
    ]

    public static let atkinsonFineRound: [CalibrationVariant] = [
        .init(id: "E01", dithering: .atkinson, threshold: 0.38),
        .init(id: "E02", dithering: .atkinson, threshold: 0.42),
        .init(id: "E03", dithering: .atkinson, threshold: 0.46),
        .init(id: "E04", dithering: .atkinson, threshold: 0.50),
        .init(id: "E05", dithering: .atkinson, threshold: 0.54),
        .init(id: "E06", dithering: .atkinson, threshold: 0.58),
        .init(id: "E07", dithering: .atkinson, threshold: 0.62),
        .init(id: "E08", dithering: .atkinson, threshold: 0.50, brightness: -0.12),
        .init(id: "E09", dithering: .atkinson, threshold: 0.50, brightness: -0.06),
        .init(id: "E10", dithering: .atkinson, threshold: 0.50, brightness: 0.06),
        .init(id: "E11", dithering: .atkinson, threshold: 0.50, brightness: 0.12),
        .init(id: "E12", dithering: .atkinson, threshold: 0.50, contrast: 0.85),
        .init(id: "E13", dithering: .atkinson, threshold: 0.50, contrast: 1.15),
        .init(id: "E14", dithering: .atkinson, threshold: 0.50, contrast: 1.30),
        .init(id: "E15", dithering: .atkinson, threshold: 0.50, contrast: 1.50),
        .init(id: "E16", dithering: .atkinson, threshold: 0.50, gamma: 0.75),
        .init(id: "E17", dithering: .atkinson, threshold: 0.50, gamma: 0.90),
        .init(id: "E18", dithering: .atkinson, threshold: 0.50, gamma: 1.10),
        .init(id: "E19", dithering: .atkinson, threshold: 0.50, gamma: 1.30),
        .init(id: "E20", dithering: .atkinson, threshold: 0.46, brightness: 0.04, contrast: 1.15, gamma: 0.90),
        .init(id: "E21", dithering: .atkinson, threshold: 0.50, brightness: 0.04, contrast: 1.15, gamma: 0.90),
        .init(id: "E22", dithering: .atkinson, threshold: 0.54, brightness: 0.04, contrast: 1.15, gamma: 0.90),
        .init(id: "E23", dithering: .atkinson, threshold: 0.50, brightness: -0.04, contrast: 1.25, gamma: 1.10),
        .init(id: "E24", dithering: .atkinson, threshold: 0.54, brightness: -0.04, contrast: 1.25, gamma: 1.10)
    ]

    public static let finalistTransportRound: [CalibrationVariant] = [
        .init(id: "F01", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 24, blePacingMilliseconds: 25, postStripDelayMilliseconds: 0),
        .init(id: "F02", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 64, blePacingMilliseconds: 25, postStripDelayMilliseconds: 0),
        .init(id: "F03", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 128, blePacingMilliseconds: 25, postStripDelayMilliseconds: 0),
        .init(id: "F04", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 256, blePacingMilliseconds: 25, postStripDelayMilliseconds: 0),
        .init(id: "F05", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 2_048, blePacingMilliseconds: 25, postStripDelayMilliseconds: 0),
        .init(id: "F06", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0),
        .init(id: "G01", dithering: .atkinson, threshold: 0.42, rasterStripHeight: 24, blePacingMilliseconds: 25, postStripDelayMilliseconds: 0),
        .init(id: "G02", dithering: .atkinson, threshold: 0.42, rasterStripHeight: 64, blePacingMilliseconds: 25, postStripDelayMilliseconds: 0),
        .init(id: "G03", dithering: .atkinson, threshold: 0.42, rasterStripHeight: 128, blePacingMilliseconds: 25, postStripDelayMilliseconds: 0),
        .init(id: "G04", dithering: .atkinson, threshold: 0.42, rasterStripHeight: 256, blePacingMilliseconds: 25, postStripDelayMilliseconds: 0),
        .init(id: "G05", dithering: .atkinson, threshold: 0.42, rasterStripHeight: 2_048, blePacingMilliseconds: 25, postStripDelayMilliseconds: 0),
        .init(id: "G06", dithering: .atkinson, threshold: 0.42, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0)
    ]

    public static let constantSpeedRound: [CalibrationVariant] = [
        .init(id: "H01", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 2),
        .init(id: "H02", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 4),
        .init(id: "H03", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 6),
        .init(id: "H04", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 8),
        .init(id: "I01", dithering: .atkinson, threshold: 0.42, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 2),
        .init(id: "I02", dithering: .atkinson, threshold: 0.42, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 4),
        .init(id: "I03", dithering: .atkinson, threshold: 0.42, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 6),
        .init(id: "I04", dithering: .atkinson, threshold: 0.42, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 8)
    ]

    public static let detailEnhancementRound: [CalibrationVariant] = [
        .init(id: "J01", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 4),
        .init(id: "J02", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 4, sharpness: 0.25),
        .init(id: "J03", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 4, sharpness: 0.50),
        .init(id: "J04", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 4, sharpness: 0.75),
        .init(id: "J05", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 4, localContrast: 0.15),
        .init(id: "J06", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 4, localContrast: 0.30),
        .init(id: "J07", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 4, sharpness: 0.35, localContrast: 0.15),
        .init(id: "J08", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 4, sharpness: 0.50, localContrast: 0.20),
        .init(id: "J09", dithering: .atkinson, threshold: 0.50, gamma: 1.30, rasterStripHeight: 2_048, blePacingMilliseconds: 10, postStripDelayMilliseconds: 0, heatingInterval: 4, sharpness: 0.65, localContrast: 0.25)
    ]

    /// Research-derived alternatives to the validated J06 photo profile.
    /// Transport, heating and J06 tone settings remain identical so the
    /// physical print is a useful one-variable comparison.
    public static let advancedQualityRound: [CalibrationVariant] = [
        .init(
            id: "Q01 Lanczos-5 resampling",
            dithering: .atkinson,
            threshold: 0.50,
            gamma: 1.30,
            rasterStripHeight: 2_048,
            blePacingMilliseconds: 10,
            postStripDelayMilliseconds: 0,
            heatingInterval: 4,
            localContrast: 0.30,
            imageProcessing: .lanczos5
        ),
        .init(
            id: "Q02 percentile contrast",
            dithering: .atkinson,
            threshold: 0.50,
            gamma: 1.30,
            rasterStripHeight: 2_048,
            blePacingMilliseconds: 10,
            postStripDelayMilliseconds: 0,
            heatingInterval: 4,
            localContrast: 0.30,
            imageProcessing: .percentileContrast
        ),
        .init(
            id: "Q03 reproducible blue noise",
            dithering: .atkinson,
            threshold: 0.50,
            gamma: 1.30,
            rasterStripHeight: 2_048,
            blePacingMilliseconds: 10,
            postStripDelayMilliseconds: 0,
            heatingInterval: 4,
            localContrast: 0.30,
            imageProcessing: .reproducibleBlueNoise
        )
    ]
}

public enum PrintAlignment: String, Codable, CaseIterable, Sendable {
    case leading
    case center
    case trailing
}

public enum ImageScalingMode: String, Codable, CaseIterable, Sendable {
    case fitWidth
    case actualSize
    case center
    case cropToWidth
}

public struct QualitySettings: Codable, Sendable, Equatable {
    public var maxHeatingDots: UInt8
    public var heatingTime: UInt8
    public var heatingInterval: UInt8
    public var brightness: Double
    public var contrast: Double
    public var gamma: Double
    public var threshold: Double
    public var dithering: DitheringAlgorithm
    public var invert: Bool
    public var sharpness: Double? = nil
    public var localContrast: Double? = nil
}

public struct TransportSettings: Codable, Sendable, Equatable {
    public var blePacingMilliseconds: Int
    public var rasterStripHeight: Int
    public var postStripDelayMilliseconds: Int
    public var preferWriteWithoutResponse: Bool
}

public struct RenderSettings: Codable, Sendable, Equatable {
    public var pageWidthPixels: Int = 384
    public var horizontalMargin: Int = 8
    public var topMargin: Int = 8
    public var bottomMargin: Int = 8
    public var textFontSize: Double = 22
    public var lineSpacing: Double = 5
    public var alignment: PrintAlignment = .leading
    public var imageScaling: ImageScalingMode = .fitWidth
}

public struct PT210GATTProfile: Codable, Sendable, Equatable {
    public let serviceUUID: String
    public let writeUUID: String
    public let notifyUUID: String?

    public static let pt210L = PT210GATTProfile(
        serviceUUID: "000018F0-0000-1000-8000-00805F9B34FB",
        writeUUID: "00002AF1-0000-1000-8000-00805F9B34FB",
        notifyUUID: "00002AF0-0000-1000-8000-00805F9B34FB"
    )

    public static let primary = PT210GATTProfile(
        serviceUUID: "49535343-FE7D-4AE5-8FA9-9FAFD205E455",
        writeUUID: "49535343-8841-43F4-A8D4-ECBE34729BB3",
        notifyUUID: "49535343-1E4D-4BD9-BA61-23C647249616"
    )

    public static let alternative = PT210GATTProfile(
        serviceUUID: "0000FF00-0000-1000-8000-00805F9B34FB",
        writeUUID: "0000FF02-0000-1000-8000-00805F9B34FB",
        notifyUUID: "0000FF01-0000-1000-8000-00805F9B34FB"
    )

    public static let known = [pt210L, primary, alternative]
}

public struct PrinterSettings: Codable, Sendable, Equatable {
    public var peripheralIdentifier: UUID?
    public var gattProfile: PT210GATTProfile?
    public var quality: QualitySettings
    public var transport: TransportSettings
    public var render: RenderSettings

    public static let balanced = PrinterSettings(
        quality: QualitySettings(
            maxHeatingDots: 7,
            heatingTime: 120,
            heatingInterval: 2,
            brightness: 0,
            contrast: 1,
            gamma: 1,
            threshold: 0.5,
            dithering: .floydSteinberg,
            invert: false
        ),
        transport: TransportSettings(
            blePacingMilliseconds: 40,
            rasterStripHeight: 24,
            postStripDelayMilliseconds: 50,
            preferWriteWithoutResponse: true
        ),
        render: RenderSettings()
    )

    public static var fast: PrinterSettings {
        var settings = balanced
        settings.quality.heatingTime = 100
        settings.quality.dithering = .bayer4x4
        settings.transport.blePacingMilliseconds = 25
        settings.transport.rasterStripHeight = 32
        settings.transport.postStripDelayMilliseconds = 35
        return settings
    }

    public static var highQuality: PrinterSettings {
        var settings = balanced
        // Hardware-calibrated H02 transport and J06 image processing profile
        // for the tested PT210L.
        settings.quality.dithering = .atkinson
        settings.quality.threshold = 0.50
        settings.quality.gamma = 1.30
        settings.quality.heatingInterval = 4
        settings.quality.sharpness = 0
        settings.quality.localContrast = 0.30
        settings.transport.blePacingMilliseconds = 10
        settings.transport.rasterStripHeight = 2_048
        settings.transport.postStripDelayMilliseconds = 0
        settings.render.horizontalMargin = 0
        return settings
    }

    public static var highQualityText: PrinterSettings {
        var settings = balanced
        // Text benefits from hard black/white edges instead of photographic
        // error-diffusion dots. A slightly higher threshold retains the
        // anti-aliased edges of glyphs and thin rules.
        settings.quality.dithering = .threshold
        settings.quality.threshold = 0.65
        settings.quality.gamma = 1
        settings.quality.sharpness = 0
        settings.quality.localContrast = 0
        settings.quality.heatingInterval = 4
        settings.transport.blePacingMilliseconds = 10
        settings.transport.rasterStripHeight = 2_048
        settings.transport.postStripDelayMilliseconds = 0
        return settings
    }
}

public struct MonochromeBitmap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let data: Data

    public init(width: Int, height: Int, bytesPerRow: Int, data: Data) throws {
        guard width > 0, height > 0, bytesPerRow == (width + 7) / 8 else {
            throw PrintError.invalidBitmap
        }
        guard data.count == height * bytesPerRow else { throw PrintError.invalidBitmap }
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.data = data
    }
}

public enum PrintJobState: Sendable, Equatable {
    case idle
    case preparing
    case rendering
    case connecting
    case configuringPrinter
    case sending(progress: Double)
    case waiting
    case completed
    case failed(String)
    case cancelled
}

public struct PrintExecutionDiagnostics: Sendable, Equatable {
    public var lastJobBytes: Int?
    public var lastDurationSeconds: Double?
    public var lastError: String?

    public init(lastJobBytes: Int? = nil, lastDurationSeconds: Double? = nil, lastError: String? = nil) {
        self.lastJobBytes = lastJobBytes
        self.lastDurationSeconds = lastDurationSeconds
        self.lastError = lastError
    }
}

public enum PrintError: LocalizedError, Sendable {
    case bluetoothUnavailable
    case printerNotFound
    case connectionFailed
    case connectionTimedOut
    case missingWriteCharacteristic
    case writeFailed
    case renderFailed
    case unsupportedContent
    case invalidBitmap
    case invalidSettings
    case storageUnavailable
    case inputTooLarge
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable: "Bluetooth is unavailable. Turn on Bluetooth and try again."
        case .printerNotFound: "The PT-210 could not be found. Check that it is turned on and nearby."
        case .connectionFailed: "The PT-210 connection failed. Turn the printer off and on, then try again."
        case .connectionTimedOut: "The PT-210 did not finish connecting. Move it closer, restart it, and try again."
        case .missingWriteCharacteristic: "The printer was found, but its print channel is unavailable."
        case .writeFailed: "The print data could not be sent. The paper may contain a partial print."
        case .renderFailed: "The content could not be prepared for printing."
        case .unsupportedContent: "This file type is not supported."
        case .invalidBitmap: "The generated print image is invalid."
        case .invalidSettings: "The printer settings are invalid."
        case .storageUnavailable: "Shared storage is unavailable. Check the App Group configuration."
        case .inputTooLarge: "This item is too large to process safely."
        case .cancelled: "Printing was cancelled. A partial print may remain."
        }
    }
}
