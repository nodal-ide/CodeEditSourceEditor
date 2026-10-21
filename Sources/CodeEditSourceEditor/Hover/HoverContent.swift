//
//  HoverContent.swift
//  CodeEditSourceEditor
//

import Foundation

/// The content shown in a hover tooltip.
///
/// Providers should prefer ``document(_:)`` when they can describe the hover semantically, use
/// ``markdown(_:)`` for Markdown content, and use ``plainText(_:)`` as a safe fallback.
public enum HoverContent: Equatable {
    /// Unformatted text. The renderer preserves line breaks.
    case plainText(String)
    /// Markdown content, including inline and block formatting.
    case markdown(String)
    /// A structured hover document with a header and semantic sections.
    case document(HoverDocument)

    /// A plain-text representation used by compatibility APIs and as a final fallback.
    public var plainText: String {
        switch self {
        case .plainText(let text), .markdown(let text):
            return text
        case .document(let document):
            return document.plainText
        }
    }

    /// Whether the content has nothing to display.
    public var isEmpty: Bool {
        plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// A structured hover document rendered by the editor.
public struct HoverDocument: Equatable {
    /// The symbol or diagnostic header, when present.
    public var header: HoverHeader?
    /// Ordered semantic sections. Empty sections are omitted by the renderer.
    public var blocks: [HoverBlock]

    public init(header: HoverHeader? = nil, blocks: [HoverBlock] = []) {
        self.header = header
        self.blocks = blocks
    }

    /// A plain-text representation of the document.
    public var plainText: String {
        var sections: [String] = []

        if let header {
            if let title = Self.nonEmpty(header.title) {
                sections.append(title)
            }
            if let subtitle = Self.nonEmpty(header.subtitle) {
                sections.append(subtitle)
            }
            if !header.badges.isEmpty {
                sections.append(header.badges.map { "[\($0.text)]" }.joined(separator: " "))
            }
        }

        for block in blocks {
            if let text = block.plainText {
                sections.append(text)
            }
        }

        return sections.joined(separator: "\n\n")
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The identity row at the top of a hover document.
public struct HoverHeader: Equatable {
    /// The primary label, usually the symbol name.
    public var title: String
    /// Supporting context, such as the containing type or namespace.
    public var subtitle: String?
    /// An SF Symbol name for the semantic kind.
    public var systemImageName: String?
    /// The semantic tint for the icon and title accents.
    public var tone: HoverTone
    /// Short labels such as `deprecated`, `static`, or `readonly`.
    public var badges: [HoverBadge]

    public init(
        title: String,
        subtitle: String? = nil,
        systemImageName: String? = nil,
        tone: HoverTone = .neutral,
        badges: [HoverBadge] = []
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImageName = systemImageName
        self.tone = tone
        self.badges = badges
    }
}

/// A short semantic label shown next to a hover header.
public struct HoverBadge: Equatable {
    public var text: String
    public var tone: HoverTone

    public init(text: String, tone: HoverTone = .neutral) {
        self.text = text
        self.tone = tone
    }
}

/// Semantic tones used by hover headers, badges, definitions, and notices.
///
/// Renderers map these values to appearance-aware colors. Tones never carry meaning on their own;
/// they are always paired with text or an icon.
public enum HoverTone: String, Equatable {
    case neutral
    case accent
    case type
    case callable
    case value
    case namespace
    case success
    case info
    case warning
    case error
}

/// An ordered section in a hover document.
public enum HoverBlock: Equatable {
    /// Markdown prose.
    case markdown(String)
    /// A symbol signature. The language hint is optional.
    case signature(HoverCode)
    /// A standalone code example. The language hint is optional.
    case code(HoverCode)
    /// A titled list of definitions, such as parameters or return values.
    case definitionList(HoverDefinitionList)
    /// A prominent notice, such as deprecation or a diagnostic message.
    case notice(HoverNotice)
    /// A set of references.
    case links([HoverLink])
    /// Muted key/value metadata, such as `@since` or `@author`.
    case metadata([HoverMetadataItem])
    /// A visual separator between sections.
    case divider
    /// A muted footer, such as a source location.
    case footer(String)

    var plainText: String? {
        switch self {
        case .markdown(let text), .footer(let text):
            return Self.nonEmpty(text)
        case .signature(let code), .code(let code):
            return Self.nonEmpty(code.text)
        case .definitionList(let list):
            let rows = list.items.compactMap(\.plainText)
            guard !rows.isEmpty else { return nil }
            var sections: [String] = []
            if let title = Self.nonEmpty(list.title) {
                sections.append(title)
            }
            sections.append(contentsOf: rows)
            return sections.joined(separator: "\n")
        case .notice(let notice):
            let title = Self.nonEmpty(notice.title)
            let message = Self.nonEmpty(notice.message)
            switch (title, message) {
            case let (title?, message?):
                return "\(title): \(message)"
            case let (title?, nil):
                return title
            case let (nil, message?):
                return message
            case (nil, nil):
                return nil
            }
        case .links(let links):
            let values = links.compactMap { link -> String? in
                guard let title = Self.nonEmpty(link.title) else { return nil }
                guard let url = link.url else { return title }
                return "\(title): \(url.absoluteString)"
            }
            return values.isEmpty ? nil : values.joined(separator: "\n")
        case .metadata(let items):
            let values = items.compactMap { item -> String? in
                let label = Self.nonEmpty(item.label)
                let value = Self.nonEmpty(item.value)
                switch (label, value) {
                case let (label?, value?):
                    return "\(label) \(value)"
                case let (label?, nil):
                    return label
                case let (nil, value?):
                    return value
                case (nil, nil):
                    return nil
                }
            }
            return values.isEmpty ? nil : values.joined(separator: "\n")
        case .divider:
            return nil
        }
    }

    fileprivate static func nonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Code shown in a signature or example block.
public struct HoverCode: Equatable {
    public var text: String
    /// A language identifier used for syntax highlighting, such as `php` or `swift`.
    public var language: String?

    public init(text: String, language: String? = nil) {
        self.text = text
        self.language = language
    }
}

/// A titled list of definitions.
public struct HoverDefinitionList: Equatable {
    public var title: String?
    public var items: [HoverDefinitionItem]

    public init(title: String? = nil, items: [HoverDefinitionItem]) {
        self.title = title
        self.items = items
    }
}

/// A definition row, such as a parameter or return value.
public struct HoverDefinitionItem: Equatable {
    /// A monospaced identifier, such as `$amount`.
    public var term: String?
    /// A type label, such as `string` or `array<string, Foo>`.
    public var type: String?
    /// An optional description. May contain inline Markdown.
    public var description: String?
    /// The semantic tone used for the type or warning indicator.
    public var tone: HoverTone

    public init(
        term: String? = nil,
        type: String? = nil,
        description: String? = nil,
        tone: HoverTone = .neutral
    ) {
        self.term = term
        self.type = type
        self.description = description
        self.tone = tone
    }

    var plainText: String? {
        let term = HoverBlock.nonEmpty(term)
        let type = HoverBlock.nonEmpty(type)
        let description = HoverBlock.nonEmpty(description)

        var label: String?
        switch (term, type) {
        case let (term?, type?):
            label = "\(term) (\(type))"
        case let (term?, nil):
            label = term
        case let (nil, type?):
            label = type
        case (nil, nil):
            label = nil
        }

        switch (label, description) {
        case let (label?, description?):
            return "\(label) — \(description)"
        case let (label?, nil):
            return label
        case let (nil, description?):
            return description
        case (nil, nil):
            return nil
        }
    }
}

/// A prominent message in a hover document.
public struct HoverNotice: Equatable {
    public var title: String?
    public var message: String
    public var tone: HoverTone

    public init(title: String? = nil, message: String, tone: HoverTone = .info) {
        self.title = title
        self.message = message
        self.tone = tone
    }
}

/// A reference shown in a hover document.
public struct HoverLink: Equatable {
    public var title: String
    /// The destination, when the reference is a link.
    public var url: URL?

    public init(title: String, url: URL? = nil) {
        self.title = title
        self.url = url
    }
}

/// A muted metadata row, such as `@since 1.2.0`.
public struct HoverMetadataItem: Equatable {
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}
