import Foundation
import UniformTypeIdentifiers

public enum ContentDetector {
    public static let maximumTextBytes = 5 * 1_024 * 1_024
    public static let supportedExtensions = Set([
        "txt", "md", "markdown", "html", "htm", "jpg", "jpeg", "png", "heic", "heif"
    ])

    public static func content(for url: URL, storedImage: StoredImageReference? = nil) throws -> PrintContent {
        let ext = url.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { throw PrintError.unsupportedContent }

        if ["jpg", "jpeg", "png", "heic", "heif"].contains(ext) {
            guard let storedImage else { throw PrintError.storageUnavailable }
            return .image(storedImage)
        }

        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard values.fileSize.map({ $0 <= maximumTextBytes }) != false else { throw PrintError.inputTooLarge }
        let text = try String(contentsOf: url, encoding: .utf8)
        return switch ext {
        case "md", "markdown": .markdown(text)
        case "html", "htm": .html(html: text, css: nil)
        default: .plainText(text)
        }
    }
}
