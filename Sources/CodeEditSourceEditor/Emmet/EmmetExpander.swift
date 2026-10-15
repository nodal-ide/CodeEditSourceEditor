//
//  EmmetExpander.swift
//  CodeEditSourceEditor
//

import Foundation

/// A small Emmet-style abbreviation expander for HTML/XML.
///
/// Supports: tag names, `#id`, `.class`, the child combinator `>`, multiplication `*N`, and text content
/// `{text}`. Expansion produces a **snippet** (using `${0}` cursors inside empty elements) so it can be
/// inserted via ``TextViewController/insertSnippet(_:replacing:)``.
public enum EmmetExpander {
    /// Expands an abbreviation into a snippet, or `nil` if it isn't a valid abbreviation.
    public static func snippet(for abbreviation: String) -> String? {
        let trimmed = abbreviation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasSuffix(">") else { return nil }
        guard let node = parseElement(trimmed) else { return nil }
        return node.render(indent: 0)
    }

    // MARK: - Parsing

    private indirect enum Node {
        case element(tag: String, id: String?, classes: [String], repeatCount: Int, children: [Node])
        case text(String)

        func render(indent: Int) -> String {
            switch self {
            case .text(let text):
                return text
            case let .element(tag, id, classes, repeatCount, children):
                let attrs = EmmetExpander.attributes(id: id, classes: classes)
                let rendered = (0..<repeatCount).map { _ -> String in
                    guard !children.isEmpty else {
                        return "<\(tag)\(attrs)>${0}</\(tag)>"
                    }
                    let inner = children
                        .map { $0.render(indent: indent + 1) }
                        .joined(separator: "\n" + String(repeating: "  ", count: indent + 1))
                    return "<\(tag)\(attrs)>\n"
                        + String(repeating: "  ", count: indent + 1)
                        + inner
                        + "\n"
                        + String(repeating: "  ", count: indent)
                        + "</\(tag)>"
                }
                return rendered.joined(separator: "\n" + String(repeating: "  ", count: indent))
            }
        }
    }

    /// Parses a `>`-separated chain of elements. The last element may carry a `*N` multiplier.
    private static func parseElement(_ string: String) -> Node? {
        // Split on `>` (not inside `{}`).
        var segments: [String] = []
        var current = ""
        var depth = 0
        for char in string {
            if char == "{" { depth += 1 }
            if char == "}" { depth -= 1 }
            if char == ">", depth == 0 {
                segments.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        segments.append(current)

        guard let first = parseSegment(segments[0]) else { return nil }
        return buildChain(base: first, remaining: Array(segments.dropFirst()))
    }

    private static func buildChain(base: SegmentNode, remaining: [String]) -> Node? {
        guard let next = remaining.first else {
            return base.node
        }
        guard let childSegment = parseSegment(next),
              let childNode = buildChain(base: childSegment, remaining: Array(remaining.dropFirst())),
              case let .element(tag, id, classes, repeatCount, children) = base.node else {
            return nil
        }
        return .element(
            tag: tag, id: id, classes: classes, repeatCount: repeatCount, children: children + [childNode]
        )
    }

    private struct SegmentNode {
        let node: Node
    }

    private static func parseSegment(_ segment: String) -> SegmentNode? {
        var segment = segment
        var repeatCount = 1

        // Trailing `*N`
        if let starIndex = segment.lastIndex(of: "*") {
            let countString = segment[segment.index(after: starIndex)...]
            if let count = Int(countString), count > 0 {
                repeatCount = min(count, 100)
                segment = String(segment[..<starIndex])
            }
        }

        // Text content `{...}`
        if segment.hasPrefix("{"), segment.hasSuffix("}"), segment.count >= 2 {
            let text = String(segment.dropFirst().dropLast())
            return SegmentNode(node: .text(text))
        }

        // tag[#id][.class...]
        var tag = ""
        var id: String?
        var classes: [String] = []
        var index = segment.startIndex
        while index < segment.endIndex, segment[index].isLetter || segment[index].isNumber {
            tag.append(segment[index])
            index = segment.index(after: index)
        }

        while index < segment.endIndex {
            let marker = segment[index]
            guard marker == "#" || marker == "." else { return nil }
            index = segment.index(after: index)
            var name = ""
            while index < segment.endIndex, segment[index] != "#", segment[index] != "." {
                name.append(segment[index])
                index = segment.index(after: index)
            }
            if marker == "#" {
                id = name
            } else if !name.isEmpty {
                classes.append(name)
            }
        }

        if tag.isEmpty {
            tag = (id != nil || !classes.isEmpty) ? "div" : ""
        }
        guard !tag.isEmpty else { return nil }

        return SegmentNode(node: .element(tag: tag, id: id, classes: classes, repeatCount: repeatCount, children: []))
    }

    // MARK: - Rendering

    private static func attributes(id: String?, classes: [String]) -> String {
        var result = ""
        if !classes.isEmpty {
            result += " class=\"\(classes.joined(separator: " "))\""
        }
        if let id {
            result += " id=\"\(id)\""
        }
        return result
    }

}
