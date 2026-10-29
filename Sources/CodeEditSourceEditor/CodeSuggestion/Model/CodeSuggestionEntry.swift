//
//  CodeSuggestionEntry.swift
//  CodeEditSourceEditor
//

import AppKit
import SwiftUI

/// Represents an item that can be displayed in the code suggestion view
public protocol CodeSuggestionEntry {
    var label: String { get }
    var detail: String? { get }
    var documentation: String? { get }

    /// Leave as `nil` if the link is in the same document.
    var pathComponents: [String]? { get }
    var targetPosition: CursorPosition? { get }
    var sourcePreview: String? { get }

    var image: Image { get }
    var imageColor: Color { get }

    var deprecated: Bool { get }

    /// Presentation kind. Defaults to `.unknown` for providers that predate kinds.
    var kind: CompletionItemKind { get }
    /// Text used for matching instead of ``label`` when present.
    var filterText: String? { get }
    /// Provider-supplied ordering key. Lower values sort first among equal match scores.
    var sortText: String? { get }
    /// Whether an item should be selected first when the query is empty.
    var preselect: Bool { get }
    /// Whether the text should be inserted as an LSP snippet (tab stops supported).
    var isSnippet: Bool { get }
}

public extension CodeSuggestionEntry {
    var kind: CompletionItemKind { .unknown }
    var filterText: String? { nil }
    var sortText: String? { nil }
    var preselect: Bool { false }
    var isSnippet: Bool { false }
}

/// The result of a completion request.
public struct CompletionResult {
    public let items: [any CodeSuggestionEntry]
    /// Whether the provider has more results for a refined query.
    public let isIncomplete: Bool

    public init(items: [any CodeSuggestionEntry], isIncomplete: Bool = false) {
        self.items = items
        self.isIncomplete = isIncomplete
    }
}
