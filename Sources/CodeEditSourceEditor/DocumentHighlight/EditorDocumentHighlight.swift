//
//  EditorDocumentHighlight.swift
//  CodeEditSourceEditor
//

import Foundation

/// A highlight of an occurrence of the symbol under the cursor (read/write/text, per LSP).
public struct EditorDocumentHighlight: Sendable, Hashable {
    /// The highlighted range (UTF-16 offsets).
    public let range: NSRange
    /// An optional kind (`1` text, `2` read, `3` write).
    public let kind: Int?

    public init(range: NSRange, kind: Int? = nil) {
        self.range = range
        self.kind = kind
    }
}

/// A delegate that provides highlights for occurrences of the symbol at a position.
@MainActor
public protocol DocumentHighlightDelegate: AnyObject {
    /// - Parameters:
    ///   - position: The cursor position to resolve highlights for.
    ///   - textView: The text view controller.
    /// - Returns: Ranges to highlight.
    func documentHighlights(
        at position: CursorPosition,
        textView: TextViewController
    ) async -> [EditorDocumentHighlight]
}
