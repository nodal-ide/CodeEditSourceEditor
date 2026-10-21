//
//  HoverContentRenderer.swift
//  CodeEditSourceEditor
//

import AppKit

/// Builds the attributed text used by the hover card.
enum HoverContentRenderer {
    static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let bodyFont = NSFont.systemFont(ofSize: 12)
    static let bodySemiboldFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let captionFont = NSFont.systemFont(ofSize: 11)
    static let captionSemiboldFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let codeFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    static let signatureFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
    static let badgeFont = NSFont.systemFont(ofSize: 10, weight: .medium)

    static let blockSpacing: CGFloat = 10
    static let maxContentLength = 32_000

    static let lineSeparator = "\u{2028}"

    static func attributedString(
        for content: HoverContent,
        theme: EditorTheme? = nil
    ) -> NSAttributedString {
        switch content {
        case .plainText(let text):
            return body(text)
        case .markdown(let text):
            return HoverMarkdownRenderer.attributedString(text, theme: theme)
        case .document(let document):
            return attributedString(for: document.blocks, theme: theme)
        }
    }

    static func attributedString(
        for blocks: [HoverBlock],
        theme: EditorTheme? = nil
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let sections = blocks.compactMap { HoverBlockRenderer.attributedString(for: $0, theme: theme) }

        for (index, section) in sections.enumerated() {
            result.append(section)
            if index < sections.count - 1 {
                result.append(NSAttributedString(
                    string: "\n",
                    attributes: bodyAttributes()
                ))
            }
        }

        return limited(result)
    }

    static func height(
        for content: HoverContent,
        width: CGFloat,
        theme: EditorTheme? = nil
    ) -> CGFloat {
        height(of: attributedString(for: content, theme: theme), width: width)
    }

    static func height(
        for blocks: [HoverBlock],
        width: CGFloat,
        theme: EditorTheme? = nil
    ) -> CGFloat {
        height(of: attributedString(for: blocks, theme: theme), width: width)
    }

    static func naturalWidth(for content: HoverContent, theme: EditorTheme? = nil) -> CGFloat {
        ceil(attributedString(for: content, theme: theme).size().width)
    }

    static func naturalWidth(for blocks: [HoverBlock], theme: EditorTheme? = nil) -> CGFloat {
        blocks.compactMap { HoverBlockRenderer.attributedString(for: $0, theme: theme) }
            .map { ceil($0.size().width) }
            .max() ?? 0
    }

    static func height(of attributed: NSAttributedString, width: CGFloat) -> CGFloat {
        guard attributed.length > 0 else { return 0 }
        return ceil(attributed.boundingRect(
            with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).height)
    }

    static func body(_ text: String) -> NSAttributedString {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return NSAttributedString() }
        return NSAttributedString(string: truncated(trimmed), attributes: bodyAttributes())
    }

    static func bodyAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle()
        ]
    }

    static func captionAttributes(
        color: NSColor = .secondaryLabelColor,
        weight: NSFont.Weight = .regular
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: weight == .semibold ? captionSemiboldFont : captionFont,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle()
        ]
    }

    static func paragraphStyle() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1
        paragraph.paragraphSpacing = blockSpacing
        return paragraph
    }

    static func truncated(_ text: String) -> String {
        guard text.count > maxContentLength else { return text }
        return String(text.prefix(maxContentLength - 1)) + "…"
    }

    private static func limited(_ attributed: NSAttributedString) -> NSAttributedString {
        guard attributed.length > maxContentLength else { return attributed }

        let string = attributed.string as NSString
        var end = maxContentLength - 1
        while end > 0, end < string.length {
            let range = string.rangeOfComposedCharacterSequence(at: end)
            guard range.location < end else { break }
            end = range.location
        }

        let result = NSMutableAttributedString(
            attributedString: attributed.attributedSubstring(from: NSRange(location: 0, length: end))
        )
        var attributes = bodyAttributes()
        if attributed.length > 0 {
            attributes = attributed.attributes(at: attributed.length - 1, effectiveRange: nil)
        }
        result.append(NSAttributedString(string: "…", attributes: attributes))
        return result
    }
}

extension HoverTone {
    var color: NSColor {
        switch self {
        case .neutral:
            return .labelColor
        case .accent:
            return .controlAccentColor
        case .type:
            return .systemPurple
        case .callable:
            return .systemBlue
        case .value:
            return .systemTeal
        case .namespace:
            return .systemIndigo
        case .success:
            return .systemGreen
        case .info:
            return .systemCyan
        case .warning:
            return .systemOrange
        case .error:
            return .systemRed
        }
    }
}
