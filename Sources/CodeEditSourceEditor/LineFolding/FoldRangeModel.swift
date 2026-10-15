//
//  FoldRangeModel.swift
//  CodeEditSourceEditor
//

import Foundation

/// Requests folding ranges from the delegate (debounced) and caches the latest result.
///
/// Rendering consumes ``ranges`` (see the folding ribbon). The language server's folding ranges are
/// line-based and complement the indentation-based ``LineFoldProvider``.
@MainActor
final class FoldRangeModel {
    /// Posted after ``ranges`` changes. The object is the model.
    static let didUpdateNotification = Notification.Name("FoldRangeModelDidUpdate")

    weak var delegate: FoldRangeDelegate?
    weak var controller: TextViewController?

    /// The most recently requested folding ranges.
    private(set) var ranges: [EditorFoldRange] = []

    private var task: Task<Void, Never>?

    init(controller: TextViewController?, delegate: FoldRangeDelegate?) {
        self.controller = controller
        self.delegate = delegate
    }

    /// Re-requests folding ranges after a short debounce.
    func refresh() {
        guard let delegate, let controller else { return }
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, let controller = self.controller else { return }
            let ranges = await delegate.foldRanges(for: controller)
            guard !Task.isCancelled else { return }
            self.ranges = ranges
            NotificationCenter.default.post(name: Self.didUpdateNotification, object: self)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Clears the cached ranges (e.g. when the delegate is removed).
    func clear() {
        task?.cancel()
        task = nil
        ranges = []
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: self)
    }
}
