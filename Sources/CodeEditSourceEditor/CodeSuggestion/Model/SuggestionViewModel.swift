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

    /// Row the window should keep selected after a refresh replaced the item list.
    var selectionAnchor: String?
    /// Label of the currently selected row, maintained by the window controller.
    var selectedLabel: String?

    private let session = CompletionSession()
    private var isWindowShowing = false
    private var requestGeneration = 0

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
        session.cancel()
        session.onRefresh = { [weak self] refined in
            self?.applyRefreshedItems(refined)
        }

        guard let targetParentWindow = textView.view.window else { return }

        self.activeTextView = textView
        self.delegate = delegate
        self.selectionAnchor = nil
        self.selectedLabel = nil
        requestGeneration &+= 1
        let generation = requestGeneration

        itemsRequestTask = Task { [weak self] in
            guard let self else { return }
            let result = await self.session.open(
                textView: textView,
                delegate: delegate,
                position: cursorPosition
            )
            guard self.requestGeneration == generation else { return }
            self.itemsRequestTask = nil
            guard let result, !Task.isCancelled else { return }
            guard let cursorRect = Self.cursorRect(for: textView, at: cursorPosition, in: targetParentWindow) else {
                return
            }
            self.items = result.items
            self.syntaxHighlightedCache = [:]
            self.isWindowShowing = true
            showWindowOnParent(targetParentWindow, cursorRect)
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

        switch session.update(textView: textView, position: position) {
        case .close:
            close()
        case .pending:
            items = []
        case .items(let newItems):
            items = newItems
        }
    }

    func didSelect(item: CodeSuggestionEntry) {
        selectedLabel = item.label
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
        itemsRequestTask?.cancel()
        itemsRequestTask = nil
        items.removeAll()
        activeTextView = nil
        isWindowShowing = false
        selectionAnchor = nil
        session.cancel()
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

    private func applyRefreshedItems(_ refined: [CodeSuggestionEntry]?) {
        guard isWindowShowing, activeTextView != nil else { return }
        guard let refined else {
            SuggestionController.shared.close()
            return
        }
        guard refined.map(\.label) != items.map(\.label) else { return }
        selectionAnchor = selectedLabel
        syntaxHighlightedCache = [:]
        items = refined
    }

    private static func cursorRect(
        for textView: TextViewController,
        at position: CursorPosition,
        in parentWindow: NSWindow
    ) -> NSRect? {
        guard let resolved = textView.resolveCursorPosition(position),
              let rect = textView.textView.layoutManager.rectForOffset(resolved.range.location),
              let converted = textView.view.window?.convertToScreen(textView.textView.convert(rect, to: nil)) else {
            return nil
        }
        return converted
    }
}
