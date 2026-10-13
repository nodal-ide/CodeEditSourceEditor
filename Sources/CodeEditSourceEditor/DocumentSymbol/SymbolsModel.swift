//
//  SymbolsModel.swift
//  CodeEditSourceEditor
//

import AppKit
import CodeEditTextView

/// Presents the document's symbols in the suggestion popover for quick navigation.
@MainActor
final class SymbolsModel: CodeSuggestionDelegate {
    weak var delegate: SymbolsDelegate?
    weak var controller: TextViewController?

    private var symbols: [EditorSymbol] = []
    private weak var activeTextView: TextViewController?

    init(controller: TextViewController?, delegate: SymbolsDelegate?) {
        self.controller = controller
        self.delegate = delegate
    }

    func show(at position: CursorPosition) {
        guard let controller, delegate != nil else { return }
        activeTextView = controller
        Task { [weak self] in
            guard let self, let controller = self.controller, let delegate = self.delegate else { return }
            let symbols = await delegate.documentSymbols(for: controller)
            guard !Task.isCancelled else { return }
            guard !symbols.isEmpty else {
                NSSound.beep()
                return
            }
            self.symbols = symbols
            SuggestionController.shared.showCompletions(
                textView: controller,
                delegate: self,
                cursorPosition: position
            )
        }
    }

    // MARK: - CodeSuggestionDelegate

    func completionSuggestionsRequested(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) async -> (windowPosition: CursorPosition, items: [CodeSuggestionEntry])? {
        symbols.isEmpty ? nil : (cursorPosition, symbols)
    }

    func completionOnCursorMove(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> [CodeSuggestionEntry]? {
        symbols.isEmpty ? nil : symbols
    }

    func completionTriggerCharacters() -> Set<String> { [] }

    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) {
        guard let symbol = item as? EditorSymbol else { return }
        textView.textView.selectionManager.setSelectedRange(symbol.position.range)
        textView.textView.scrollSelectionToVisible()
        SuggestionController.shared.close()
    }
}