//
//  DiagnosticsModel.swift
//  CodeEditSourceEditor
//

import AppKit
import CodeEditTextView

/// Requests diagnostics from the delegate (debounced) and renders them as underlines.
@MainActor
final class DiagnosticsModel {
    private static let emphasisID = "diagnostics"

    weak var delegate: DiagnosticsDelegate?
    weak var controller: TextViewController?

    private var task: Task<Void, Never>?

    init(controller: TextViewController?, delegate: DiagnosticsDelegate?) {
        self.controller = controller
        self.delegate = delegate
    }

    /// Recompute diagnostics after a short debounce.
    func refresh() {
        guard let delegate, let controller else { return }
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let diagnostics = await delegate.diagnostics(for: controller)
            guard !Task.isCancelled else { return }
            self?.apply(diagnostics)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private func apply(_ diagnostics: [EditorDiagnostic]) {
        guard let textView = controller?.textView, let manager = textView.emphasisManager else { return }
        let length = textView.textStorage?.length ?? 0

        // Cap the number of rendered underlines so a pathological file can't create thousands
        // of layers.
        let limited = diagnostics.count > Self.maxRendered
            ? Array(diagnostics.prefix(Self.maxRendered))
            : diagnostics

        // Drop any diagnostic whose range no longer fits the current text (the parse may be
        // from a slightly older snapshot than the live buffer).
        let emphases = limited.compactMap { diagnostic -> Emphasis? in
            let range = diagnostic.range
            guard range.location >= 0, range.length >= 0, range.location + range.length <= length else {
                return nil
            }
            return Emphasis(
                range: range,
                style: .underline(color: Self.color(for: diagnostic.severity)),
                inactive: true
            )
        }
        manager.replaceEmphases(emphases, for: Self.emphasisID)
        manager.updateLayerBackgrounds()
    }

    private static let maxRendered = 300

    private static func color(for severity: EditorDiagnosticSeverity) -> NSColor {
        switch severity {
        case .error: return .systemRed
        case .warning: return .systemOrange
        case .info: return .systemBlue
        case .hint: return .systemGray
        }
    }
}