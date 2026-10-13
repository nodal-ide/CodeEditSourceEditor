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
        guard let manager = controller?.textView?.emphasisManager else { return }
        let emphases = diagnostics.map { diagnostic in
            Emphasis(
                range: diagnostic.range,
                style: .underline(color: Self.color(for: diagnostic.severity)),
                inactive: true
            )
        }
        manager.replaceEmphases(emphases, for: Self.emphasisID)
        manager.updateLayerBackgrounds()
    }

    private static func color(for severity: EditorDiagnosticSeverity) -> NSColor {
        switch severity {
        case .error: return .systemRed
        case .warning: return .systemOrange
        case .info: return .systemBlue
        case .hint: return .systemGray
        }
    }
}