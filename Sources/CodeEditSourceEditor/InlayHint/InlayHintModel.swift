//
//  InlayHintModel.swift
//  CodeEditSourceEditor
//

import AppKit
import CodeEditTextView

/// Requests inlay hints for the visible range (debounced), caches by (range, content), and renders them
/// as inline attachments.
@MainActor
final class InlayHintModel {
    weak var delegate: InlayHintDelegate?
    weak var controller: TextViewController?

    private var task: Task<Void, Never>?
    /// Cache key for the last successfully requested range/content.
    private var lastRange: NSRange?
    private var lastContentHash: Int?

    init(controller: TextViewController?, delegate: InlayHintDelegate?) {
        self.controller = controller
        self.delegate = delegate
    }

    /// Re-requests inlay hints for the visible range after a short debounce. Skips the request when the
    /// visible range and content are unchanged since the last request.
    func refresh() {
        guard delegate != nil, let controller, let textView = controller.textView else { return }
        guard let range = textView.visibleTextRange else {
            clear()
            return
        }

        // The content hash is O(visible range); compute it inside the debounced task (once it settles)
        // rather than synchronously on every keystroke.
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self, let delegate = self.delegate,
                  let controller = self.controller, let textView = controller.textView else { return }
            let contentHash = self.hash(of: range, in: textView)
            if range == self.lastRange, contentHash == self.lastContentHash {
                return
            }
            let hints = await delegate.inlayHints(forVisibleRange: range, textView: controller)
            guard !Task.isCancelled else { return }
            self.lastRange = range
            self.lastContentHash = contentHash
            self.apply(hints, in: textView)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Removes all rendered hints and resets the cache.
    func clear() {
        lastRange = nil
        lastContentHash = nil
        controller?.textView?.layoutManager.attachments.removeAllInlayHints()
    }

    func invalidate() {
        lastRange = nil
        lastContentHash = nil
    }

    private func apply(_ hints: [EditorInlayHint], in textView: TextView) {
        textView.layoutManager.attachments.removeAllInlayHints()

        let length = textView.textStorage?.length ?? 0
        let font = NSFont.monospacedSystemFont(ofSize: controller?.font.pointSize ?? 12, weight: .regular)
        for hint in hints where hint.offset >= 0 && hint.offset <= length && !hint.text.isEmpty {
            let attachment = InlayHintAttachment(
                text: hint.text,
                font: font,
                textColor: .secondaryLabelColor,
                backgroundColor: NSColor.controlBackgroundColor.withAlphaComponent(0.55)
            )
            textView.layoutManager.attachments.addInlayHint(attachment, at: hint.offset)
        }
    }

    private func hash(of range: NSRange, in textView: TextView) -> Int {
        guard let storage = textView.textStorage,
              range.location >= 0, NSMaxRange(range) <= storage.length else {
            return 0
        }
        return storage.attributedSubstring(from: range).string.hashValue
    }
}
