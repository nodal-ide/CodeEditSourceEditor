//
//  DocumentHighlightModel.swift
//  CodeEditSourceEditor
//

import AppKit
import CodeEditTextView

/// Resolves occurrences of the symbol under the cursor (debounced on cursor moves) and renders them as
/// background emphases.
@MainActor
final class DocumentHighlightModel {
    private static let emphasisID = "documentHighlight"

    weak var delegate: DocumentHighlightDelegate?
    weak var controller: TextViewController?

    private var task: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    init(controller: TextViewController?, delegate: DocumentHighlightDelegate?) {
        self.controller = controller
        self.delegate = delegate
    }

    /// Begins observing cursor moves, and resolves highlights for the current position.
    func start() {
        guard observer == nil, let controller else { return }
        observer = NotificationCenter.default.addObserver(
            forName: TextViewController.cursorPositionUpdatedNotification,
            object: controller,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func refresh() {
        guard let delegate, let controller, let position = controller.cursorPositions.first else {
            clear()
            return
        }
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, let controller = self.controller else { return }
            let highlights = await delegate.documentHighlights(at: position, textView: controller)
            guard !Task.isCancelled else { return }
            self.apply(highlights)
        }
    }

    func clear() {
        guard let manager = controller?.textView.emphasisManager else { return }
        manager.removeEmphases(for: Self.emphasisID)
        manager.updateLayerBackgrounds()
    }

    private func apply(_ highlights: [EditorDocumentHighlight]) {
        guard let manager = controller?.textView.emphasisManager else { return }
        let length = controller?.textView.textStorage?.length ?? 0
        let emphases = highlights.compactMap { highlight -> Emphasis? in
            let range = highlight.range
            guard range.location >= 0, NSMaxRange(range) <= length else { return nil }
            return Emphasis(range: range, style: .standard, inactive: true)
        }
        manager.replaceEmphases(emphases, for: Self.emphasisID)
        manager.updateLayerBackgrounds()
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
