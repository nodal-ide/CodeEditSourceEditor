//
//  HoverMarkdownRenderer.swift
//  CodeEditSourceEditor
//

import AppKit
import CodeEditLanguages

/// Renders Markdown hover content into attributed text.
enum HoverMarkdownRenderer {
    private struct Run {
        let text: String
        let inlineIntent: InlinePresentationIntent?
        let link: URL?
    }

    private enum BlockKind {
        case heading(Int)
        case paragraph
        case listItem(ordinal: Int, ordered: Bool)
        case quote
        case code(languageHint: String?)
        case thematicBreak
    }

    private struct Block {
        let kind: BlockKind
        var runs: [Run] = []
    }

    static func attributedString(_ markdown: String, theme: EditorTheme?) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return HoverContentRenderer.body(markdown)
        }

        let blocks = blocks(from: parsed)
        guard !blocks.isEmpty else { return HoverContentRenderer.body(markdown) }

        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            result.append(attributedString(for: block, theme: theme))
            if index < blocks.count - 1 {
                result.append(NSAttributedString(
                    string: "\n",
                    attributes: HoverContentRenderer.bodyAttributes()
                ))
            }
        }
        return result
    }

    private static func blocks(from parsed: AttributedString) -> [Block] {
        var blocks: [Block] = []
        var currentIdentity: Int?

        for run in parsed.runs {
            let intent = run.presentationIntent
            let identity = intent?.components.first?.identity ?? -1
            if blocks.isEmpty || identity != currentIdentity {
                currentIdentity = identity
                blocks.append(Block(kind: blockKind(from: intent)))
            }

            blocks[blocks.count - 1].runs.append(Run(
                text: String(parsed[run.range].characters),
                inlineIntent: run.inlinePresentationIntent,
                link: run.link
            ))
        }

        return blocks
    }

    private static func blockKind(from intent: PresentationIntent?) -> BlockKind {
        guard let components = intent?.components else { return .paragraph }

        for component in components {
            switch component.kind {
            case .header(let level):
                return .heading(level)
            case .codeBlock(let languageHint):
                return .code(languageHint: languageHint)
            case .listItem(let ordinal):
                let ordered = components.contains {
                    if case .orderedList = $0.kind {
                        return true
                    }
                    return false
                }
                return .listItem(ordinal: ordinal, ordered: ordered)
            case .blockQuote:
                return .quote
            case .thematicBreak:
                return .thematicBreak
            default:
                continue
            }
        }
        return .paragraph
    }

    private static func attributedString(for block: Block, theme: EditorTheme?) -> NSAttributedString {
        switch block.kind {
        case .code(let languageHint):
            let text = block.runs.map(\.text).joined().trimmingCharacters(in: .newlines)
            return HoverCodeStyler.attributedString(
                text: text,
                languageHint: languageHint,
                font: HoverContentRenderer.codeFont,
                theme: theme,
                paragraphStyle: paragraphStyle(for: block.kind)
            )
        case .thematicBreak:
            return NSAttributedString(
                string: "────────",
                attributes: [
                    .font: HoverContentRenderer.captionFont,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .paragraphStyle: paragraphStyle(for: block.kind)
                ]
            )
        default:
            return inlineAttributedString(for: block, theme: theme)
        }
    }

    private static func inlineAttributedString(for block: Block, theme: EditorTheme?) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if let prefix = prefix(for: block.kind) {
            result.append(NSAttributedString(
                string: prefix,
                attributes: baseAttributes(for: block.kind)
            ))
        }

        for run in block.runs {
            result.append(NSAttributedString(
                string: run.text,
                attributes: attributes(for: run, kind: block.kind)
            ))
        }
        return result
    }

    private static func attributes(
        for run: Run,
        kind: BlockKind
    ) -> [NSAttributedString.Key: Any] {
        var attributes = baseAttributes(for: kind)
        var font = attributes[.font] as? NSFont ?? HoverContentRenderer.bodyFont

        if let inlineIntent = run.inlineIntent {
            if inlineIntent.contains(.stronglyEmphasized) {
                font = fontByAddingTrait(.bold, to: font)
            }
            if inlineIntent.contains(.emphasized) {
                font = fontByAddingTrait(.italic, to: font)
            }
            if inlineIntent.contains(.code) {
                font = HoverContentRenderer.codeFont
                attributes[.backgroundColor] = NSColor.textBackgroundColor.withAlphaComponent(0.45)
            }
            if inlineIntent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
        }
        attributes[.font] = font

        if let url = HoverURLPolicy.safe(run.link) {
            attributes[.link] = url
            attributes[.foregroundColor] = NSColor.controlAccentColor
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    private static func baseAttributes(for kind: BlockKind) -> [NSAttributedString.Key: Any] {
        let paragraph = paragraphStyle(for: kind)
        switch kind {
        case .heading(let level):
            return [
                .font: level == 1 ? HoverContentRenderer.titleFont : HoverContentRenderer.bodySemiboldFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        case .quote:
            return [
                .font: fontByAddingTrait(.italic, to: HoverContentRenderer.bodyFont),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]
        default:
            return [
                .font: HoverContentRenderer.bodyFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        }
    }

    private static func paragraphStyle(for kind: BlockKind) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 1

        switch kind {
        case .heading:
            paragraph.paragraphSpacing = 6
        case .listItem(_, let ordered):
            paragraph.paragraphSpacing = 2
            paragraph.headIndent = ordered ? 18 : 14
        case .quote:
            paragraph.paragraphSpacing = 8
            paragraph.headIndent = 13
        default:
            paragraph.paragraphSpacing = 8
        }
        return paragraph
    }

    private static func prefix(for kind: BlockKind) -> String? {
        switch kind {
        case .listItem(let ordinal, let ordered):
            return ordered ? "\(ordinal). " : "• "
        case .quote:
            return "│ "
        default:
            return nil
        }
    }

    private static func fontByAddingTrait(
        _ trait: NSFontDescriptor.SymbolicTraits,
        to font: NSFont
    ) -> NSFont {
        var traits = font.fontDescriptor.symbolicTraits
        traits.insert(trait)
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
}

/// Applies syntax highlighting to hover code when a theme and language are available.
enum HoverCodeStyler {
    private static let aliases: [String: String] = [
        "c#": "csharp",
        "c++": "cpp",
        "js": "javascript",
        "md": "markdown",
        "py": "python",
        "rb": "ruby",
        "sh": "bash",
        "shell": "bash",
        "ts": "typescript",
        "yml": "yaml"
    ]

    static func attributedString(
        text: String,
        languageHint: String?,
        font: NSFont,
        theme: EditorTheme?,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let trimmed = text.trimmingCharacters(in: .newlines)
        guard !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NSAttributedString()
        }

        let background = (theme?.background ?? NSColor.textBackgroundColor).withAlphaComponent(0.55)
        if let theme,
           let language = language(for: languageHint),
           let highlighted = TreeSitterClient.quickHighlight(
               string: trimmed,
               theme: theme,
               font: font,
               language: language
           ) {
            let result = NSMutableAttributedString(attributedString: highlighted)
            result.addAttributes(
                [
                    .paragraphStyle: paragraphStyle,
                    .backgroundColor: background
                ],
                range: NSRange(location: 0, length: result.length)
            )
            return result
        }

        return NSAttributedString(
            string: trimmed,
            attributes: [
                .font: font,
                .foregroundColor: theme?.text.color ?? NSColor.labelColor,
                .paragraphStyle: paragraphStyle,
                .backgroundColor: background
            ]
        )
    }

    static func language(for hint: String?) -> CodeLanguage? {
        guard let hint else { return nil }
        let raw = hint
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .first
            .map(String.init)?
            .lowercased()
        guard let raw, !raw.isEmpty else { return nil }
        let normalized = aliases[raw] ?? raw

        return CodeLanguage.allLanguages.first {
            $0.tsName.lowercased() == normalized
                || $0.extensions.contains(normalized)
                || $0.additionalIdentifiers.contains(normalized)
        }
    }
}
