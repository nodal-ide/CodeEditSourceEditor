//
//  CodeActionModel.swift
//  CodeEditSourceEditor
//

import AppKit
import CodeEditTextView

/// Requests code actions for the current cursor and presents them in the suggestion popover.
/// Applies the chosen action's edits to the text view.
@MainActor
final class CodeActionModel: CodeSuggestionDelegate {
    weak var delegate: CodeActionDelegate?
    weak var controller: TextViewController?

    private var actions: [CodeActionInfo] = []
    private weak var activeTextView: TextViewController?

    init(controller: TextViewController?, delegate: CodeActionDelegate?) {
        self.controller = controller
        self.delegate = delegate
    }

    func showActions(at position: CursorPosition) {
        guard let controller, let delegate else { return }
        activeTextView = controller
        let range = position.range

        Task { [weak self] in
            guard let self, let controller = self.controller else { return }
            let actions = await delegate.codeActions(forRange: range, textView: controller)
            guard !Task.isCancelled else { return }
            guard !actions.isEmpty else {
                NSSound.beep()
                return
            }
            self.actions = actions
            if actions.count == 1 {
                self.apply(actions[0])
                return
            }
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
        actions.isEmpty ? nil : (cursorPosition, actions)
    }

    func completionOnCursorMove(
        textView: TextViewController,
        cursorPosition: CursorPosition
    ) -> [CodeSuggestionEntry]? {
        actions.isEmpty ? nil : actions
    }

    func completionTriggerCharacters() -> Set<String> { [] }

    func completionWindowApplyCompletion(
        item: CodeSuggestionEntry,
        textView: TextViewController,
        cursorPosition: CursorPosition?
    ) {
        guard let action = item as? CodeActionInfo else { return }
        apply(action)
    }

    // MARK: - Apply

    private func apply(_ action: CodeActionInfo) {
        guard let textView = activeTextView?.textView else { return }
        // Apply edits bottom-to-top so earlier ranges stay valid.
        for edit in action.edits.sorted(by: { $0.range.location > $1.range.location }) {
            textView.replaceCharacters(in: edit.range, with: edit.text)
        }
        SuggestionController.shared.close()
    }
}