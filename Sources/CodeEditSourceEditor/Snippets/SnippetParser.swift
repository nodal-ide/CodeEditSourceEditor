//
//  SnippetParser.swift
//  CodeEditSourceEditor
//

import Foundation

/// A tab stop within a parsed snippet.
public struct SnippetStop: Equatable {
    /// The stop's index. `0` is the final cursor position.
    public let index: Int
    /// The stop's range in the parsed (literal) text, using UTF-16 offsets.
    public let range: NSRange
}

/// The result of parsing a snippet.
public struct ParsedSnippet {
    /// The literal text with all snippet markers removed.
    public let text: String
    /// The tab stops, in document order.
    public let stops: [SnippetStop]

    public var isEmpty: Bool { stops.isEmpty && text.isEmpty }
}

/// Parses LSP snippet syntax (<https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#snippet_syntax>).
///
/// Supported: `$N`, `${N}`, `${N:default}`, `${N|choice1,choice2|}`, `${N:...}`/`$0` final stop, and the
/// escapes `\$`, `\}`, `\\`, `\|`, `\,`, `\n`, `\t`. Nested placeholders are not supported.
public enum SnippetParser {
    public static func parse(_ snippet: String) -> ParsedSnippet {
        let output = NSMutableString()
        var stops: [SnippetStop] = []
        let chars = Array(snippet)
        var index = 0

        func append(_ string: String) {
            output.append(string)
        }

        while index < chars.count {
            let char = chars[index]

            // Escapes
            if char == "\\", index + 1 < chars.count {
                switch chars[index + 1] {
                case "$": append("$")
                case "}": append("}")
                case "\\": append("\\")
                case "|": append("|")
                case ",": append(",")
                case "n": append("\n")
                case "t": append("\t")
                default: append(String(chars[index + 1]))
                }
                index += 2
                continue
            }

            guard char == "$", index + 1 < chars.count else {
                append(String(char))
                index += 1
                continue
            }

            // `$$` is a literal dollar sign.
            if chars[index + 1] == "$" {
                append("$")
                index += 2
                continue
            }

            let next = chars[index + 1]

            // `${...}`
            if next == "{" {
                guard let (stop, nextIndex) = parseBraced(chars, from: index, output: output) else {
                    append("$")
                    index += 1
                    continue
                }
                stops.append(stop)
                index = nextIndex
                continue
            }

            // `$N`
            if next.isNumber {
                var cursor = index + 1
                var number = ""
                while cursor < chars.count, chars[cursor].isNumber {
                    number.append(chars[cursor])
                    cursor += 1
                }
                if let stopIndex = Int(number) {
                    let location = output.length
                    stops.append(SnippetStop(index: stopIndex, range: NSRange(location: location, length: 0)))
                    index = cursor
                    continue
                }
            }

            // Not a valid marker: literal `$`.
            append("$")
            index += 1
        }

        // Ensure there is a final `$0` stop.
        if !stops.contains(where: { $0.index == 0 }) {
            stops.append(SnippetStop(index: 0, range: NSRange(location: output.length, length: 0)))
        }

        return ParsedSnippet(text: output as String, stops: stops)
    }

    /// Parses a `${...}` construct starting at `start` (which points at `$`).
    private static func parseBraced(
        _ chars: [Character],
        from start: Int,
        output: NSMutableString
    ) -> (SnippetStop, Int)? {
        var cursor = start + 2
        var number = ""
        while cursor < chars.count, chars[cursor].isNumber {
            number.append(chars[cursor])
            cursor += 1
        }
        guard !number.isEmpty, let stopIndex = Int(number), cursor < chars.count else {
            return nil
        }

        switch chars[cursor] {
        case "}":
            let location = output.length
            return (SnippetStop(index: stopIndex, range: NSRange(location: location, length: 0)), cursor + 1)

        case ":":
            var text = ""
            var index = cursor + 1
            var depth = 1
            while index < chars.count, depth > 0 {
                let char = chars[index]
                if char == "\\" , index + 1 < chars.count {
                    text.append(char)
                    text.append(chars[index + 1])
                    index += 2
                    continue
                }
                if char == "{" { depth += 1 }
                if char == "}" {
                    depth -= 1
                    if depth == 0 { break }
                }
                text.append(char)
                index += 1
            }
            let literal = parse(text).text
            let location = output.length
            output.append(literal)
            let length = (literal as NSString).length
            return (
                SnippetStop(index: stopIndex, range: NSRange(location: location, length: length)),
                min(index + 1, chars.count)
            )

        case "|":
            var choice = ""
            var index = cursor + 1
            while index < chars.count, chars[index] != "|" {
                choice.append(chars[index])
                index += 1
            }
            let first = choice
                .split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init) ?? ""
            let literal = first.replacingOccurrences(of: "\\,", with: ",")
            let location = output.length
            output.append(literal)
            let length = (literal as NSString).length
            return (
                SnippetStop(index: stopIndex, range: NSRange(location: location, length: length)),
                min(index + 1, chars.count)
            )

        default:
            return nil
        }
    }
}
