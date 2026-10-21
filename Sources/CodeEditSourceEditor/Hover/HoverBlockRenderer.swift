//
//  HoverBlockRenderer.swift
//  CodeEditSourceEditor
//

import AppKit

/// Builds the attributed text for individual semantic hover blocks.
enum HoverBlockRenderer {
    static func attributedString(
        for block: HoverBlock,
        theme: EditorTheme? = nil
    ) -> NSAttributedString? {
        switch block {
        case .markdown(let text):
            return HoverMarkdownRenderer.attributedString(text, theme: theme)
        case .signature(let code):
            return codeBlock(code, font: HoverContentRenderer.signatureFont, theme: theme)
        case .code(let code):
            return codeBlock(code, font: HoverContentRenderer.codeFont, theme: theme)
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

    private static func codeBlock(
        _ code: HoverCode,
        font: NSFont,
        theme: EditorTheme?
    ) -> NSAttributedString? {
        let trimmed = code.text.trimmingCharacters(in: .newlines)
        guard !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return HoverCodeStyler.attributedString(
            text: HoverContentRenderer.truncated(trimmed),
            languageHint: code.language,
            font: font,
            theme: theme,
            paragraphStyle: HoverContentRenderer.paragraphStyle()
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
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        result.addAttribute(
            .backgroundColor,
            value: notice.tone.color.withAlphaComponent(highContrast ? 0.22 : 0.10),
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }

    private static func linksBlock(_ links: [HoverLink]) -> NSAttributedString? {
        let rows = links.compactMap { link -> NSAttributedString? in
            let title = link.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            var attributes = HoverContentRenderer.bodyAttributes()
            if let url = HoverURLPolicy.safe(link.url) {
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

}
