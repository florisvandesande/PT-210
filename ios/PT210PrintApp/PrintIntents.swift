import AppIntents
import PT210PrintCore
import UniformTypeIdentifiers

enum ShortcutTextFormat: String, AppEnum {
    case plainText, markdown, html
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Text format")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .plainText: "Plain text", .markdown: "Markdown", .html: "HTML"
    ]
}

enum ShortcutQuality: String, AppEnum {
    case text, imageHighQuality, custom
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Quality")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .text: "Text", .imageHighQuality: "Image (High quality)", .custom: "Custom"
    ]
}

enum ShortcutImageScaling: String, AppEnum {
    case fitWidth, actualSize, center, cropToWidth
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Image scaling")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .fitWidth: "Fit width", .actualSize: "Actual size",
        .center: "Center", .cropToWidth: "Square crop"
    ]
}

struct PrintTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Print text on PT-210"
    static let description = IntentDescription("Prints plain text, Markdown, or HTML using the saved PT-210 printer.")
#if targetEnvironment(macCatalyst)
    @available(macOS 26.0, iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground(.immediate)
    @available(macOS 27.0, iOS 27.0, *)
    static let allowedExecutionTargets: IntentExecutionTargets = .main
#else
    static let openAppWhenRun = false
#endif

    @Parameter(title: "Text") var text: String
    @Parameter(title: "Format", default: .plainText) var format: ShortcutTextFormat
    @Parameter(title: "CSS", default: "") var css: String
    @Parameter(title: "Quality", default: .text) var quality: ShortcutQuality
    @Parameter(title: "Copies", default: 1, inclusiveRange: (1, 20)) var copies: Int
    @Parameter(title: "Feed lines", default: 3, inclusiveRange: (0, 20)) var feedLines: Int
    @Parameter(title: "Prepare for preview", default: false) var preview: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Print \(\.$text) as \(\.$format)") {
            \.$css; \.$quality; \.$copies; \.$feedLines; \.$preview
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let content: PrintContent = switch format {
        case .plainText: .plainText(text)
        case .markdown: .markdown(text)
        case .html: .html(html: text, css: css.isEmpty ? nil : css)
        }
        let job = makeJob(content: content, quality: quality, copies: copies, feedLines: feedLines)
        if preview {
            try await PrintJobStore().savePending(job)
            return .result(dialog: "Prepared in PT-210 Print")
        }
        try await print(job: job)
        return .result(dialog: "Printed successfully")
    }
}

struct PrintImageIntent: AppIntent {
    static let title: LocalizedStringResource = "Print image on PT-210"
    static let description = IntentDescription("Prints a JPEG, PNG, HEIC, or HEIF image on the saved PT-210 printer.")
#if targetEnvironment(macCatalyst)
    @available(macOS 26.0, iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground(.immediate)
    @available(macOS 27.0, iOS 27.0, *)
    static let allowedExecutionTargets: IntentExecutionTargets = .main
#else
    static let openAppWhenRun = false
#endif

    @Parameter(title: "Image", supportedContentTypes: [.image]) var image: IntentFile
    @Parameter(title: "Quality", default: .imageHighQuality) var quality: ShortcutQuality
    @Parameter(title: "Scaling", default: .fitWidth) var scaling: ShortcutImageScaling
    @Parameter(title: "Copies", default: 1, inclusiveRange: (1, 20)) var copies: Int
    @Parameter(title: "Feed lines", default: 3, inclusiveRange: (0, 20)) var feedLines: Int
    @Parameter(title: "Prepare for preview", default: false) var preview: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var settings = try await SharedSettingsStore().load()
        settings.render.imageScaling = ImageScalingMode(rawValue: scaling.rawValue) ?? .fitWidth
        try await SharedSettingsStore().save(settings)
        let (reference, assetURL) = try await importIntentImage(image)
        let job = makeJob(content: .image(reference), quality: quality, copies: copies, feedLines: feedLines)
        if preview {
            try await PrintJobStore().savePending(job)
            return .result(dialog: "Prepared in PT-210 Print")
        }
        try await print(job: job, assetURL: assetURL)
        return .result(dialog: "Printed successfully")
    }
}

struct PrintFileIntent: AppIntent {
    static let title: LocalizedStringResource = "Print file on PT-210"
    static let description = IntentDescription("Detects and prints a supported text, Markdown, HTML, or image file.")
#if targetEnvironment(macCatalyst)
    @available(macOS 26.0, iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground(.immediate)
    @available(macOS 27.0, iOS 27.0, *)
    static let allowedExecutionTargets: IntentExecutionTargets = .main
#else
    static let openAppWhenRun = false
#endif

    @Parameter(title: "File", supportedContentTypes: [.data, .text, .image, .html]) var file: IntentFile
    @Parameter(title: "Quality", default: .text) var quality: ShortcutQuality
    @Parameter(title: "Copies", default: 1, inclusiveRange: (1, 20)) var copies: Int
    @Parameter(title: "Feed lines", default: 3, inclusiveRange: (0, 20)) var feedLines: Int
    @Parameter(title: "Prepare for preview", default: false) var preview: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let temporaryURL = try temporaryFile(for: file)
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let extensionName = temporaryURL.pathExtension.lowercased()
        let store = try PrintJobStore()
        let imageExtensions = Set(["jpg", "jpeg", "png", "heic", "heif"])
        let reference = imageExtensions.contains(extensionName)
            ? try await store.importAsset(from: temporaryURL, fileExtension: extensionName)
            : nil
        let content = try ContentDetector.content(for: temporaryURL, storedImage: reference)
        let job = makeJob(content: content, quality: quality, copies: copies, feedLines: feedLines)
        if preview {
            try await store.savePending(job)
            return .result(dialog: "Prepared in PT-210 Print")
        }
        try await print(job: job, assetURL: reference == nil ? nil : temporaryURL)
        return .result(dialog: "Printed successfully")
    }
}

struct PT210Shortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PrintTextIntent(), phrases: ["Print text with \(.applicationName)"], shortTitle: "Print text", systemImageName: "text.page")
        AppShortcut(intent: PrintImageIntent(), phrases: ["Print image with \(.applicationName)"], shortTitle: "Print image", systemImageName: "photo")
        AppShortcut(intent: PrintFileIntent(), phrases: ["Print file with \(.applicationName)"], shortTitle: "Print file", systemImageName: "doc")
    }
}

private func makeJob(content: PrintContent, quality: ShortcutQuality, copies: Int, feedLines: Int) -> PrintJob {
    PrintJob(content: content, qualityPresetID: quality.rawValue, copies: copies, feedLinesAfter: feedLines, source: .shortcut)
}

@MainActor
private func print(job: PrintJob, assetURL: URL? = nil) async throws {
    let bluetooth = PT210BluetoothManager()
    try await PrintJobExecutor(bluetooth: bluetooth).execute(job, assetURL: assetURL)
}

private func temporaryFile(for file: IntentFile) throws -> URL {
    let safeName = URL(fileURLWithPath: file.filename).lastPathComponent
    guard !safeName.isEmpty, file.data.count <= 25 * 1_024 * 1_024 else { throw PrintError.inputTooLarge }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + safeName)
    try file.data.write(to: url, options: .atomic)
    return url
}

private func importIntentImage(_ file: IntentFile) async throws -> (StoredImageReference, URL) {
    let temporaryURL = try temporaryFile(for: file)
    defer { try? FileManager.default.removeItem(at: temporaryURL) }
    let extensionName = temporaryURL.pathExtension.isEmpty ? (file.type?.preferredFilenameExtension ?? "img") : temporaryURL.pathExtension
    let store = try PrintJobStore()
    let reference = try await store.importAsset(from: temporaryURL, fileExtension: extensionName)
    return (reference, await store.assetURL(for: reference))
}
