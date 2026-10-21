//
//  CaptureNames.swift
//  CodeEditSourceEditor
//
//  Created by Lukas Pistrol on 16.08.22.
//

/// A collection of possible syntax capture types. Represented by an integer for memory efficiency, and with the
/// ability to convert to and from strings for ease of use with tools.
///
/// This is `Int8` raw representable for memory considerations. In large documents there can be *lots* of these created
/// and passed around, so representing them with a single integer is preferable to a string to save memory.
///
public enum CaptureName: Int8, CaseIterable, Sendable {
    case include
    case constructor
    case keyword
    case boolean
    case `repeat`
    case conditional
    case tag
    case comment
    case variable
    case property
    case function
    case method
    case number
    case float
    case string
    case type
    case parameter
    case typeAlternate
    case constant
    case character
    case `operator`
    case variableBuiltin
    case keywordReturn
    case keywordFunction

    var alternate: CaptureName {
        switch self {
        case .type:
            return .typeAlternate
        default:
            return self
        }
    }

    private static let exactCaptureNames: [String: CaptureName] = [
        "include": .include,
        "constructor": .constructor,
        "keyword": .keyword,
        "boolean": .boolean,
        "repeat": .repeat,
        "conditional": .conditional,
        "tag": .tag,
        "comment": .comment,
        "variable": .variable,
        "property": .property,
        "function": .function,
        "method": .method,
        "number": .number,
        "float": .float,
        "string": .string,
        "type": .type,
        "parameter": .parameter,
        "type_alternate": .typeAlternate,
        "constant": .constant,
        "character": .character,
        "operator": .operator,
        "variable.builtin": .variableBuiltin,
        "keyword.return": .keywordReturn,
        "keyword.function": .keywordFunction,
        "escape": .character,
        "field": .property,
        "import": .keyword,
        "preproc": .keyword,
        "storageclass": .keyword,
        "media": .keyword,
        "supports": .keyword,
        "keyframes": .keyword,
        "try": .keyword,
        "throw": .keyword,
        "finally": .keyword,
        "synchronized": .keyword,
        "selector": .function,
        "symbol": .variable
    ]

    private static let ignoredCaptureNames: Set<String> = [
        "none", "spell", "nospell", "ignore", "embedded"
    ]

    private static let ignoredCapturePrefixes = ["_", "punctuation."]

    private static let capturePrefixes: [(prefix: String, capture: CaptureName)] = [
        ("function.method", .method),
        ("function.", .function),
        ("method", .method),
        ("constant.", .constant),
        ("string.escape", .character),
        ("character.", .character),
        ("operator", .operator),
        ("attribute", .typeAlternate),
        ("label", .typeAlternate),
        ("namespace", .type),
        ("module", .type),
        ("interface", .type),
        ("protocol", .type),
        ("implementation", .type),
        ("variable.parameter", .parameter),
        ("variable.member", .property),
        ("variable.", .variable),
        ("parameter.", .parameter),
        ("property.", .property),
        ("field", .property),
        ("type.", .type),
        ("keyword.", .keyword),
        ("string.", .string),
        ("comment.", .comment),
        ("number.", .number),
        ("float.", .float),
        ("text.literal", .string),
        ("text.uri", .string),
        ("text.title", .type),
        ("text.reference", .variable)
    ]

    /// Returns a specific capture name case from a given string.
    /// - Note: See ``CaptureName`` docs for why this enum isn't a raw representable.
    /// - Parameter string: A string to get the capture name from
    /// - Returns: A `CaptureNames` case
    public static func fromString(_ string: String?) -> CaptureName? {
        guard let string else { return nil }
        let name = string.lowercased()
        if let capture = exactCaptureNames[name] {
            return capture
        }
        return captureNameForDottedName(name)
    }

    private static func captureNameForDottedName(_ name: String) -> CaptureName? {
        guard !ignoredCaptureNames.contains(name),
              !ignoredCapturePrefixes.contains(where: { name.hasPrefix($0) }) else {
            return nil
        }
        for rule in capturePrefixes where name.hasPrefix(rule.prefix) {
            return rule.capture
        }
        return nil
    }

    /// See ``CaptureName`` docs for why this enum isn't a raw representable.
    var stringValue: String {
        switch self {
        case .include:
            return "include"
        case .constructor:
            return "constructor"
        case .keyword:
            return "keyword"
        case .boolean:
            return "boolean"
        case .repeat:
            return "`repeat`"
        case .conditional:
            return "conditional"
        case .tag:
            return "tag"
        case .comment:
            return "comment"
        case .variable:
            return "variable"
        case .property:
            return "property"
        case .function:
            return "function"
        case .method:
            return "method"
        case .number:
            return "number"
        case .float:
            return "float"
        case .string:
            return "string"
        case .type:
            return "type"
        case .parameter:
            return "parameter"
        case .typeAlternate:
            return "typeAlternate"
        case .constant:
            return "constant"
        case .character:
            return "character"
        case .operator:
            return "operator"
        case .variableBuiltin:
            return "variableBuiltin"
        case .keywordReturn:
            return "keywordReturn"
        case .keywordFunction:
            return "keywordFunction"
        }
    }
}

extension CaptureName: CustomDebugStringConvertible {
    public var debugDescription: String { stringValue }
}
