//
//  SuggestionViewModel.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 7/22/25.
//

import AppKit

@MainActor
final class SuggestionViewModel: ObservableObject {
    /// The items to be displayed in the window
    @Published var items: [CodeSuggestionEntry] = []
    var itemsRequestTask: Task<Void, Never>?
    weak var activeTextView: TextViewController?

    weak var delegate: CodeSuggestionDelegate?

    private var cursorPosition: CursorPosition?
    private var syntaxHighlightedCache: [Int: NSAttributedString] = [:]

    func showCompletions(
        textView: TextViewController,
        delegate: CodeSuggestionDelegate,
        cursorPosition: CursorPosition,
        showWindowOnParent: @escaping @MainActor (NSWindow, NSRect) -> Void
    ) {
        self.activeTextView = nil
        self.delegate = nil
        itemsRequestTask?.cancel()

        guard let targetParentWindow = textView.view.window else {
            print("[suggest] showCompletions: no parent window")
            return
        }

        self.activeTextView = textView
        self.delegate = delegate
        itemsRequestTask = Task {
            defer { itemsRequestTask = nil }

            do {
                guard let completionItems = await delegate.completionSuggestionsRequested(
                    textView: textView,
                    cursorPosition: cursorPosition
                ) else {
                    print("[suggest] showCompletions: delegate returned nil")
                    return
                }

                try Task.checkCancellation()
                try await MainActor.run {
                    try Task.checkCancellation()

                    guard let cursorPosition = textView.resolveCursorPosition(completionItems.windowPosition) else {
                        print("[suggest] showCompletions: resolveCursorPosition nil")
                        return
                    }
                    guard let cursorRect = textView.textView.layoutManager.rectForOffset(
                        cursorPosition.range.location
                    ) else {
                        print("[suggest] showCompletions: rectForOffset nil")
                        return
                    }
                    guard let cursorRect = textView.view.window?.convertToScreen(
                        textView.textView.convert(cursorRect, to: nil)
                    ) else {
                        print("[suggest] showCompletions: convertToScreen nil")
                        return
                    }

                    print("[suggest] showCompletions: showing \(completionItems.items.count) items "
                          + "vm=\(ObjectIdentifier(self))")
                    self.items = completionItems.items
                    print("[suggest] vm set items=\(self.items.count) vm=\(ObjectIdentifier(self))")
                    self.syntaxHighlightedCache = [:]
                    showWindowOnParent(targetParentWindow, cursorRect)
                }
            } catch {
                print("[suggest] showCompletions error: \(error)")
                return
            }
        }
    }

    func cursorsUpdated(
        textView: TextViewController,
        delegate: CodeSuggestionDelegate,
        position: CursorPosition,
        close: () -> Void
    ) {
        guard itemsRequestTask == nil else { return }

        if activeTextView !== textView {
            close()
            return
        }

        guard let newItems = delegate.completionOnCursorMove(
            textView: textView,
            cursorPosition: position
        ),
              !newItems.isEmpty else {
            close()
            return
        }

        items = newItems
    }

    func didSelect(item: CodeSuggestionEntry) {
        delegate?.completionWindowDidSelect(item: item)
    }

    func applySelectedItem(item: CodeSuggestionEntry, window: NSWindow?) {
        guard let activeTextView else {
            return
        }
        self.delegate?.completionWindowApplyCompletion(
            item: item,
            textView: activeTextView,
            cursorPosition: activeTextView.cursorPositions.first
        )
        window?.close()
    }

    func willClose() {
        print("[suggest] willClose vm=\(ObjectIdentifier(self)) (items were \(items.count))")
        // Cancel a pending request so it can't re-show the window after the user dismissed it.
        itemsRequestTask?.cancel()
        itemsRequestTask = nil
        items.removeAll()
        activeTextView = nil
    }

    func syntaxHighlights(forIndex index: Int) -> NSAttributedString? {
        if let cached = syntaxHighlightedCache[index] {
            return cached
        }

        if let sourcePreview = items[index].sourcePreview,
           let theme = activeTextView?.theme,
           let font = activeTextView?.font,
           let language = activeTextView?.language {
            let string = TreeSitterClient.quickHighlight(
                string: sourcePreview,
                theme: theme,
                font: font,
                language: language
            )
            syntaxHighlightedCache[index] = string
            return string
        }

        return nil
    }
}
