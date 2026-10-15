//
//  FoldRangeDelegate.swift
//  CodeEditSourceEditor
//

import Foundation

/// A folding region expressed in whole lines (0-based), as returned by a language server.
public struct EditorFoldRange: Sendable, Hashable {
    /// The first line of the fold (0-based).
    public let startLine: Int
    /// The last line of the fold (0-based, inclusive).
    public let endLine: Int
    /// An optional kind hint (e.g. `comment`, `imports`, `region`).
    public let kind: String?

    public init(startLine: Int, endLine: Int, kind: String? = nil) {
        self.startLine = startLine
        self.endLine = endLine
        self.kind = kind
    }
}

/// A delegate that provides folding ranges for a document. Ranges are line-based and may come from a
/// language server (LSP `textDocument/foldingRange`).
@MainActor
public protocol FoldRangeDelegate: AnyObject {
    /// - Parameter textView: The text view controller.
    /// - Returns: Folding ranges for the entire document.
    func foldRanges(for textView: TextViewController) async -> [EditorFoldRange]
}
