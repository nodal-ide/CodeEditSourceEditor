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
    /// The diagnostics currently rendered (validated against the live buffer).
    private var current: [EditorDiagnostic] = []

    private var diagnosticsObserver: NSObjectProtocol?

    init(controller: TextViewController?, delegate: DiagnosticsDelegate?) {
        self.controller = controller
        self.delegate = delegate
        // Push-based servers (e.g. typescript-language-server) notify us to refresh.
        diagnosticsObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("LSPDiagnosticsUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit {
        if let diagnosticsObserver {
            NotificationCenter.default.removeObserver(diagnosticsObserver)
        }
    }

    /// The diagnostic covering `offset`, if any (used for hover tooltips).
    func diagnostic(at offset: Int) -> EditorDiagnostic? {
        current.first { diagnostic in
            offset >= diagnostic.range.location
                && offset <= diagnostic.range.location + max(diagnostic.range.length, 0)
        }
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
        guard let textView = controller?.textView, let manager = textView.emphasisManager else {
            current = []
            return
        }
        let length = textView.textStorage?.length ?? 0

        // Cap the number of rendered underlines so a pathological file can't create thousands
        // of layers.
        let limited = diagnostics.count > Self.maxRendered
            ? Array(diagnostics.prefix(Self.maxRendered))
            : diagnostics

        // Drop any diagnostic whose range no longer fits the current text (the parse may be
        // from a slightly older snapshot than the live buffer).
        let valid = limited.filter { diagnostic in
            let range = diagnostic.range
            return range.location >= 0 && range.length >= 0 && range.location + range.length <= length
        }
        current = valid

        let emphases = valid.map { diagnostic in
            Emphasis(
                range: diagnostic.range,
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