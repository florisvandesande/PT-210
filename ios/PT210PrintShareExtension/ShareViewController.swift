import PT210PrintCore
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(extensionContext: extensionContext)
        let host = UIHostingController(rootView: ShareView(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }
}

@MainActor
@Observable
private final class ShareModel {
    private weak var context: NSExtensionContext?
    var status = String(localized: "Loading…")
    var content: PrintContent?
    var isWorking = false
    var errorMessage: String?
    var assetURL: URL?
    var preview: UIImage?
    var quality: PrintQualityPresetID = .imageHighQuality
    var copies = 1
    var feedLines = 3

    init(extensionContext: NSExtensionContext?) {
        context = extensionContext
        Task { await load() }
    }

    func prepare() {
        guard let content else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let store = try PrintJobStore()
                let job = makeJob(content)
                try await store.savePending(job)
                context?.completeRequest(returningItems: nil)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func printNow() {
        guard let content else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                let bluetooth = PT210BluetoothManager()
                let executor = PrintJobExecutor(bluetooth: bluetooth)
                let job = makeJob(content)
                try await executor.execute(job, assetURL: assetURL)
                context?.completeRequest(returningItems: nil)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func cancel() { context?.cancelRequest(withError: PrintError.cancelled) }

    private func makeJob(_ content: PrintContent) -> PrintJob {
        PrintJob(
            content: content,
            qualityPresetID: quality.rawValue,
            copies: copies,
            feedLinesAfter: feedLines,
            source: .shareExtension
        )
    }

    private func load() async {
        let items = context?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
        guard let provider = providers.first else {
            errorMessage = PrintError.unsupportedContent.localizedDescription
            return
        }
        do {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                let data = try await provider.loadData(forTypeIdentifier: UTType.image.identifier)
                guard data.count <= 25 * 1_024 * 1_024 else { throw PrintError.inputTooLarge }
                let registeredType = provider.registeredTypeIdentifiers
                    .compactMap(UTType.init)
                    .first(where: { $0.conforms(to: .image) })
                let extensionName = registeredType?.preferredFilenameExtension ?? "img"
                let temporaryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(extensionName)
                try data.write(to: temporaryURL, options: .atomic)
                let store = try PrintJobStore()
                let reference = try await store.importAsset(from: temporaryURL, fileExtension: extensionName)
                try? FileManager.default.removeItem(at: temporaryURL)
                content = .image(reference)
                quality = .imageHighQuality
                assetURL = await store.assetURL(for: reference)
                status = String(localized: "Image ready")
            } else if provider.hasItemConformingToTypeIdentifier(UTType.html.identifier) {
                let data = try await provider.loadData(forTypeIdentifier: UTType.html.identifier)
                content = .html(html: try string(from: data), css: nil)
                quality = .text
                status = String(localized: "HTML ready")
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                let data = try await provider.loadData(forTypeIdentifier: UTType.plainText.identifier)
                content = .plainText(try string(from: data))
                quality = .text
                status = String(localized: "Text ready")
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                let temporaryURL = try await provider.loadFileCopy()
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                let ext = temporaryURL.pathExtension.lowercased()
                let store = try PrintJobStore()
                let imageExtensions = Set(["jpg", "jpeg", "png", "heic", "heif"])
                let reference = imageExtensions.contains(ext)
                    ? try await store.importAsset(from: temporaryURL, fileExtension: ext)
                    : nil
                content = try ContentDetector.content(for: temporaryURL, storedImage: reference)
                quality = reference == nil ? .text : .imageHighQuality
                if let reference { assetURL = await store.assetURL(for: reference) }
                status = String(localized: "File ready")
            } else {
                throw PrintError.unsupportedContent
            }
            await makePreview()
        } catch { errorMessage = error.localizedDescription }
    }

    private func makePreview() async {
        guard let content else { return }
        do {
            let executor = PrintJobExecutor(bluetooth: PT210BluetoothManager())
            let bitmap = try await executor.preview(makeJob(content), assetURL: assetURL)
            preview = try previewImage(from: bitmap)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func previewImage(from bitmap: MonochromeBitmap) throws -> UIImage {
        var pixels = Data(repeating: 255, count: bitmap.width * bitmap.height)
        for y in 0..<bitmap.height {
            for x in 0..<bitmap.width {
                let byte = bitmap.data[y * bitmap.bytesPerRow + x / 8]
                if byte & UInt8(0x80 >> (x % 8)) != 0 { pixels[y * bitmap.width + x] = 0 }
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

    private func string(from data: Data) throws -> String {
        if let string = String(data: data, encoding: .utf8) { return string }
        throw PrintError.unsupportedContent
    }
}

private struct ShareView: View {
    @Bindable var model: ShareModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Shared content") { Text(model.status) }
                if let preview = model.preview {
                    Section("Thermal preview") {
                        Image(uiImage: preview)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(maxHeight: 260)
                            .frame(maxWidth: .infinity)
                    }
                }
                Section("Print options") {
                    Picker("Quality", selection: $model.quality) {
                        Text("Text").tag(PrintQualityPresetID.text)
                        Text("Image (High quality)").tag(PrintQualityPresetID.imageHighQuality)
                        Text("Custom").tag(PrintQualityPresetID.custom)
                    }
                    Stepper("Copies: \(model.copies)", value: $model.copies, in: 1...20)
                    Stepper("Feed lines: \(model.feedLines)", value: $model.feedLines, in: 0...20)
                }
                if let error = model.errorMessage {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                }
                Section {
                    Button("Print now", systemImage: "printer", action: model.printNow)
                        .disabled(model.content == nil || model.isWorking)
                    Button("Prepare in PT-210 Print", action: model.prepare)
                        .disabled(model.content == nil || model.isWorking)
                }
            }
            .navigationTitle("PT-210 Print")
            .toolbar { Button("Cancel", action: model.cancel) }
        }
    }
}

private extension NSItemProvider {
    @MainActor
    func loadData(forTypeIdentifier identifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
                if let error { continuation.resume(throwing: error) }
                else if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: PrintError.unsupportedContent) }
            }
        }
    }

    @MainActor
    func loadFileCopy() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            loadFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw PrintError.unsupportedContent }
                    let destination = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
