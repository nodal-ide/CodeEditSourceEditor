//
//  EditorInlayHint.swift
//  CodeEditSourceEditor
//

import Foundation

/// An inline hint (ghost text) to render at a document offset without modifying the document.
public struct EditorInlayHint: Sendable, Hashable {
    /// The document offset the hint is placed at.
    public let offset: Int
    /// The hint text to render.
    public let text: String

    public init(offset: Int, text: String) {
        self.offset = offset
        self.text = text
    }
}

/// A delegate that provides inlay hints for the editor. Hints are requested for the visible range and
/// re-requested when the text or visible range changes.
@MainActor
public protocol InlayHintDelegate: AnyObject {
    /// - Parameters:
    ///   - range: The visible range (UTF-16 offsets) hints are requested for.
    ///   - textView: The text view controller.
    /// - Returns: Inlay hints to render inline.
    func inlayHints(forVisibleRange range: NSRange, textView: TextViewController) async -> [EditorInlayHint]
}
