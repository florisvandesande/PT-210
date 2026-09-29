import CoreGraphics
import Foundation
import UIKit

public enum TextRenderer {
    public static func render(_ content: PrintContent, settings: RenderSettings) throws -> CGImage {
        let attributed: NSAttributedString
        switch content {
        case .plainText(let text):
            attributed = NSAttributedString(
                string: normalizeHorizontalRules(in: text),
                attributes: attributes(settings)
            )
        case .markdown(let markdown):
            let value = try AttributedString(
                markdown: normalizeMarkdownForPrint(markdown),
                options: .init(interpretedSyntax: .full)
            )
            let mutable = NSMutableAttributedString(value)
            mutable.addAttributes(attributes(settings), range: NSRange(location: 0, length: mutable.length))
            applyMarkdownListIndentation(to: mutable, settings: settings)
            attributed = mutable
        case .html, .image:
            throw PrintError.unsupportedContent
        }
        guard attributed.length > 0 else { throw PrintError.renderFailed }

        let width = CGFloat(max(1, settings.pageWidthPixels - settings.horizontalMargin * 2))
        let bounds = attributed.boundingRect(
            with: CGSize(width: width, height: 100_000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).integral
        let format = UIGraphicsImageRendererFormat()
        // Render type above the printer's native resolution before reducing it
        // to 384 dots. This stabilizes curves and diagonal strokes.
        format.scale = 3
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: max(1, bounds.height)), format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: renderer.format.bounds.size))
            attributed.draw(
                with: CGRect(origin: .zero, size: renderer.format.bounds.size),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }.cgImage!
    }

    private static func normalizeHorizontalRules(in text: String) -> String {
        let ruleCharacters = CharacterSet(charactersIn: "-–—_─━")
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let value = String(line)
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                guard trimmed.count >= 3,
                      trimmed.unicodeScalars.allSatisfy(ruleCharacters.contains) else {
                    return value
                }
                return String(repeating: "─", count: trimmed.count)
            }
            .joined(separator: "\n")
    }

    /// `AttributedString(markdown:)` stores list bullets as presentation
    /// metadata. That metadata is lost when UIKit draws the resulting
    /// NSAttributedString, which previously joined every list item together.
    /// Convert list markers into printable glyphs and CommonMark hard breaks.
    private static func normalizeMarkdownForPrint(_ markdown: String) -> String {
        let normalizedRules = normalizeHorizontalRules(in: markdown)
        return normalizedRules
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { sourceLine -> String? in
                let line = String(sourceLine)
                let leadingCount = line.prefix { $0 == " " || $0 == "\t" }.count
                let leading = String(line.prefix(leadingCount))
                let trimmed = String(line.dropFirst(leadingCount))

                let listMarker = ["- ", "* ", "+ "].first { trimmed.hasPrefix($0) }
                let listBody = listMarker.map { String(trimmed.dropFirst($0.count)) } ?? trimmed
                let lowercaseBody = listBody.lowercased()
                if lowercaseBody.hasPrefix("[ ] ") || lowercaseBody.hasPrefix("[x] ") {
                    let item = listBody.dropFirst(4).trimmingCharacters(in: .whitespaces)
                    guard !item.isEmpty else { return nil }
                    let checkbox = lowercaseBody.hasPrefix("[x] ") ? "☒" : "☐"
                    return "\(leading)\(checkbox)\t\(item)  "
                }

                if let listMarker {
                    let item = trimmed.dropFirst(listMarker.count).trimmingCharacters(in: .whitespaces)
                    guard !item.isEmpty else { return nil }
                    return "\(leading)•\t\(item)  "
                }

                guard !trimmed.isEmpty else { return "" }
                return line.hasSuffix("  ") ? line : line + "  "
            }
            .joined(separator: "\n")
    }

    private static func applyMarkdownListIndentation(
        to attributed: NSMutableAttributedString,
        settings: RenderSettings
    ) {
        let value = attributed.string as NSString
        var location = 0
        while location < value.length {
            let paragraphRange = value.paragraphRange(for: NSRange(location: location, length: 0))
            let paragraph = value.substring(with: paragraphRange)
            let markerLocation = paragraph.firstIndex { ["•", "☐", "☒"].contains($0) }
            let prefixIsWhitespace = markerLocation.map {
                paragraph[..<$0].allSatisfy { $0 == " " || $0 == "\t" }
            } ?? false

            if markerLocation != nil, prefixIsWhitespace {
                let style = NSMutableParagraphStyle()
                style.lineSpacing = settings.lineSpacing
                style.firstLineHeadIndent = 0
                style.headIndent = 28
                style.tabStops = [NSTextTab(textAlignment: .left, location: 28)]
                style.defaultTabInterval = 28
                attributed.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
            }
            location = NSMaxRange(paragraphRange)
        }
    }

    private static func attributes(_ settings: RenderSettings) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = settings.lineSpacing
        paragraph.alignment = switch settings.alignment {
        case .leading: .left
        case .center: .center
        case .trailing: .right
        }
        return [
            .font: UIFont.systemFont(ofSize: settings.textFontSize),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph
        ]
    }
}
