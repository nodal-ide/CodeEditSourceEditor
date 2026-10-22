//
//  EditorSymbol.swift
//  CodeEditSourceEditor
//

import Foundation
import SwiftUI

/// A document symbol for the "Go to Symbol" outline.
public struct EditorSymbol: CodeSuggestionEntry, Identifiable {
    public let id = UUID()
    public let name: String
    public let detail: String?
    /// Jump target within the document.
    public let position: CursorPosition
    public let languageContext: LanguageZoneContext?

    public var label: String { name }
    public var documentation: String? { nil }
    public var pathComponents: [String]? { nil }
    public var targetPosition: CursorPosition? { position }
    public var sourcePreview: String? { nil }
    public var image: Image { Image(systemName: "list.bullet") }
    public var imageColor: Color { Color(NSColor.secondaryLabelColor) }
    public var deprecated: Bool { false }

    public init(
        name: String,
        detail: String?,
        position: CursorPosition,
        languageContext: LanguageZoneContext? = nil
    ) {
        self.name = name
        self.detail = detail
        self.position = position
        self.languageContext = languageContext
    }
}

/// A delegate that provides the document's symbols for navigation.
@MainActor
public protocol SymbolsDelegate: AnyObject {
    func documentSymbols(for textView: TextViewController) async -> [EditorSymbol]
}
