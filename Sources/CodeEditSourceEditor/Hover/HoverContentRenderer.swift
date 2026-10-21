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

    fileprivate static let lineSeparator = "\u{2028}"

    static func attributedString(for content: HoverContent) -> NSAttributedString {
        switch content {
        case .plainText(let text), .markdown(let text):
            return body(text)
        case .document(let document):
            return attributedString(for: document.blocks)
        }
    }

    static func attributedString(for blocks: [HoverBlock]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let sections = blocks.compactMap(HoverBlockRenderer.attributedString(for:))

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

    static func height(for content: HoverContent, width: CGFloat) -> CGFloat {
        height(of: attributedString(for: content), width: width)
    }

    static func height(for blocks: [HoverBlock], width: CGFloat) -> CGFloat {
        height(of: attributedString(for: blocks), width: width)
    }

    static func naturalWidth(for content: HoverContent) -> CGFloat {
        ceil(attributedString(for: content).size().width)
    }

    static func naturalWidth(for blocks: [HoverBlock]) -> CGFloat {
        blocks.compactMap(HoverBlockRenderer.attributedString(for:))
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

    fileprivate static func body(_ text: String) -> NSAttributedString {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return NSAttributedString() }
        return NSAttributedString(string: truncated(trimmed), attributes: bodyAttributes())
    }

    fileprivate static func bodyAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: bodyFont,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle()
        ]
    }

    fileprivate static func captionAttributes(
        color: NSColor = .secondaryLabelColor,
        weight: NSFont.Weight = .regular
    ) -> [NSAttributedString.Key: Any] {
        [
            .font: weight == .semibold ? captionSemiboldFont : captionFont,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle()
        ]
    }

    fileprivate static func paragraphStyle() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1
        paragraph.paragraphSpacing = blockSpacing
        return paragraph
    }

    fileprivate static func truncated(_ text: String) -> String {
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

/// Builds the attributed text for individual semantic hover blocks.
enum HoverBlockRenderer {
    static func attributedString(for block: HoverBlock) -> NSAttributedString? {
        switch block {
        case .markdown(let text):
            return HoverContentRenderer.body(text)
        case .signature(let code):
            return codeBlock(code, font: HoverContentRenderer.signatureFont)
        case .code(let code):
            return codeBlock(code, font: HoverContentRenderer.codeFont)
        case .definitionList(let list):
            return definitionList(list)
        case .notice(let notice):
            return noticeBlock(notice)
        case .links(let links):
            return linksBlock(links)
        case .metadata(let items):
            return metadataBlock(items)
        case .divider:
            return nil
        case .footer(let text):
            guard !text.isEmpty else { return nil }
            return NSAttributedString(
                string: HoverContentRenderer.truncated(text),
                attributes: HoverContentRenderer.captionAttributes(color: .secondaryLabelColor)
            )
        }
    }

    private static func codeBlock(_ code: HoverCode, font: NSFont) -> NSAttributedString? {
        let trimmed = code.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var attributes = HoverContentRenderer.bodyAttributes()
        attributes[.font] = font
        attributes[.backgroundColor] = NSColor.textBackgroundColor.withAlphaComponent(0.45)
        attributes[.foregroundColor] = NSColor.labelColor
        return NSAttributedString(
            string: HoverContentRenderer.truncated(trimmed),
            attributes: attributes
        )
    }

    private static func definitionList(_ list: HoverDefinitionList) -> NSAttributedString? {
        let rows = list.items.compactMap(definitionRow)
        guard !rows.isEmpty else { return nil }

        let result = NSMutableAttributedString()
        if let title = list.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            result.append(NSAttributedString(
                string: title,
                attributes: HoverContentRenderer.captionAttributes(
                    color: .secondaryLabelColor,
                    weight: .semibold
                )
            ))
            result.append(NSAttributedString(
                string: HoverContentRenderer.lineSeparator,
                attributes: HoverContentRenderer.bodyAttributes()
            ))
        }

        for (index, row) in rows.enumerated() {
            result.append(row)
            if index < rows.count - 1 {
                result.append(NSAttributedString(
                    string: HoverContentRenderer.lineSeparator,
                    attributes: HoverContentRenderer.bodyAttributes()
                ))
            }
        }

        return result
    }

    private static func definitionRow(_ item: HoverDefinitionItem) -> NSAttributedString? {
        let result = NSMutableAttributedString()
        let term = item.term?.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = item.type?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = item.description?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let term, !term.isEmpty {
            result.append(NSAttributedString(
                string: term,
                attributes: [
                    .font: HoverContentRenderer.codeFont,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: HoverContentRenderer.paragraphStyle()
                ]
            ))
        }
        if let type, !type.isEmpty {
            if result.length > 0 {
                result.append(NSAttributedString(
                    string: " ",
                    attributes: HoverContentRenderer.bodyAttributes()
                ))
            }
            result.append(NSAttributedString(
                string: "(\(type))",
                attributes: [
                    .font: HoverContentRenderer.codeFont,
                    .foregroundColor: item.tone.color,
                    .paragraphStyle: HoverContentRenderer.paragraphStyle()
                ]
            ))
        }
        if let description, !description.isEmpty {
            if result.length > 0 {
                result.append(NSAttributedString(
                    string: " — ",
                    attributes: HoverContentRenderer.captionAttributes()
                ))
            }
            result.append(NSAttributedString(
                string: HoverContentRenderer.truncated(description),
                attributes: HoverContentRenderer.bodyAttributes()
            ))
        }

        return result.length > 0 ? result : nil
    }

    private static func noticeBlock(_ notice: HoverNotice) -> NSAttributedString? {
        let result = NSMutableAttributedString()
        let title = notice.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = notice.message.trimmingCharacters(in: .whitespacesAndNewlines)

        if let title, !title.isEmpty {
            result.append(NSAttributedString(
                string: title,
                attributes: [
                    .font: HoverContentRenderer.bodySemiboldFont,
                    .foregroundColor: notice.tone.color,
                    .paragraphStyle: HoverContentRenderer.paragraphStyle()
                ]
            ))
        }
        if !message.isEmpty {
            if result.length > 0 {
                result.append(NSAttributedString(
                    string: " ",
                    attributes: HoverContentRenderer.bodyAttributes()
                ))
            }
            result.append(NSAttributedString(
                string: HoverContentRenderer.truncated(message),
                attributes: HoverContentRenderer.bodyAttributes()
            ))
        }

        guard result.length > 0 else { return nil }
        result.addAttribute(
            .backgroundColor,
            value: notice.tone.color.withAlphaComponent(0.10),
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }

    private static func linksBlock(_ links: [HoverLink]) -> NSAttributedString? {
        let rows = links.compactMap { link -> NSAttributedString? in
            let title = link.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            var attributes = HoverContentRenderer.bodyAttributes()
            if let url = safeURL(link.url) {
                attributes[.link] = url
                attributes[.foregroundColor] = NSColor.controlAccentColor
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            return NSAttributedString(string: title, attributes: attributes)
        }
        guard !rows.isEmpty else { return nil }

        let result = NSMutableAttributedString()
        for (index, row) in rows.enumerated() {
            result.append(row)
            if index < rows.count - 1 {
                result.append(NSAttributedString(
                    string: HoverContentRenderer.lineSeparator,
                    attributes: HoverContentRenderer.bodyAttributes()
                ))
            }
        }
        return result
    }

    private static func metadataBlock(_ items: [HoverMetadataItem]) -> NSAttributedString? {
        let rows = items.compactMap { item -> NSAttributedString? in
            let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = item.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty || !value.isEmpty else { return nil }

            let row = NSMutableAttributedString()
            if !label.isEmpty {
                row.append(NSAttributedString(
                    string: label,
                    attributes: HoverContentRenderer.captionAttributes(
                        color: .secondaryLabelColor,
                        weight: .semibold
                    )
                ))
            }
            if !value.isEmpty {
                if row.length > 0 {
                    row.append(NSAttributedString(
                        string: " ",
                        attributes: HoverContentRenderer.captionAttributes()
                    ))
                }
                row.append(NSAttributedString(
                    string: value,
                    attributes: HoverContentRenderer.captionAttributes()
                ))
            }
            return row
        }
        guard !rows.isEmpty else { return nil }

        let result = NSMutableAttributedString()
        for (index, row) in rows.enumerated() {
            result.append(row)
            if index < rows.count - 1 {
                result.append(NSAttributedString(
                    string: HoverContentRenderer.lineSeparator,
                    attributes: HoverContentRenderer.captionAttributes()
                ))
            }
        }
        return result
    }

    private static func safeURL(_ url: URL?) -> URL? {
        guard let url, let scheme = url.scheme?.lowercased() else { return nil }
        guard ["http", "https", "mailto"].contains(scheme) else { return nil }
        return url
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
