//
//  CodeActionDelegate.swift
//  CodeEditSourceEditor
//

import Foundation
import SwiftUI

/// A single text edit that makes up a code action.
public struct CodeActionEdit {
    public let range: NSRange
    public let text: String

    public init(range: NSRange, text: String) {
        self.range = range
        self.text = text
    }
}

/// A quick-fix / refactor action offered for a range in the editor.
///
/// Conforms to ``CodeSuggestionEntry`` so it can be presented in the existing suggestion
/// popover as a chooser.
public struct CodeActionInfo: CodeSuggestionEntry, Identifiable {
    public let id = UUID()
    public let title: String
    /// Edits to apply, in ascending order (the editor applies them bottom-to-top).
    public let edits: [CodeActionEdit]

    public var label: String { title }
    public var detail: String? { kind }
    public let kind: String?
    public let languageContext: LanguageZoneContext?
    public var documentation: String? { nil }
    public var pathComponents: [String]? { nil }
    public var targetPosition: CursorPosition? { nil }
    public var sourcePreview: String? { nil }
    public var image: Image { Image(systemName: "lightbulb") }
    public var imageColor: Color { Color(NSColor.systemYellow) }
    public var deprecated: Bool { false }

    public init(
        title: String,
        kind: String? = nil,
        edits: [CodeActionEdit],
        languageContext: LanguageZoneContext? = nil
    ) {
        self.title = title
        self.kind = kind
        self.edits = edits
        self.languageContext = languageContext
    }
}

/// A delegate that provides code actions (quick fixes / refactors) for a range.
@MainActor
public protocol CodeActionDelegate: AnyObject {
    /// - Parameters:
    ///   - range: The range a code action is requested for (usually the cursor).
    ///   - textView: The text view controller.
    /// - Returns: Available code actions (may be empty).
    func codeActions(forRange range: NSRange, textView: TextViewController) async -> [CodeActionInfo]
}
