//
//  HoverModel.swift
//  CodeEditSourceEditor
//

import AppKit
import CodeEditTextView

/// Manages hover detection: after the mouse rests over an identifier for a short dwell
/// period, it asks the ``HoverDelegate`` for content and presents a tooltip.
@MainActor
final class HoverModel {
    weak var delegate: HoverDelegate?
    weak var treeSitterClient: TreeSitterClient?
    weak var controller: TextViewController?
    /// Diagnostics are shown in preference to symbol info when the pointer is over one.
    weak var diagnosticsModel: DiagnosticsModel?

    private var hoverTask: Task<Void, Never>?
    private var currentRange: NSRange?

    private static let dwell: Duration = .milliseconds(350)

    init(controller: TextViewController?, treeSitterClient: TreeSitterClient?, delegate: HoverDelegate?) {
        self.controller = controller
        self.treeSitterClient = treeSitterClient
        self.delegate = delegate
    }

    /// Called on mouse move. `windowCoordinates` is `event.locationInWindow`.
    func mouseMoved(windowCoordinates: CGPoint) {
        guard let controller, let textView = controller.textView else {
            cancel()
            return
        }

        let textViewCoords = textView.convert(windowCoordinates, from: nil)
        guard let location = textView.layoutManager.textOffsetAtPoint(textViewCoords),
              location < textView.textStorage.length else {
            cancel()
            return
        }

        // Still inside the currently hovered identifier: keep the tooltip.
        if let currentRange, currentRange.contains(location) {
            return
        }

        cancel()
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: Self.dwell)
            guard !Task.isCancelled else { return }
            await self?.present(at: location, windowCoordinates: windowCoordinates)
        }
    }

    private func present(at location: Int, windowCoordinates: CGPoint) async {
        guard let controller, let textView = controller.textView,
              let window = controller.view.window else { return }

        // Diagnostics take priority over symbol info.
        if let diagnostic = diagnosticsModel?.diagnostic(at: location), !Task.isCancelled {
            let anchor = diagnostic.range.length > 0
                ? diagnostic.range
                : NSRange(location: diagnostic.range.location, length: 1)
            guard let rect = textView.layoutManager.rectsFor(range: anchor).first else { return }
            currentRange = diagnostic.range
            let windowRect = textView.convert(rect, to: nil)
            HoverController.shared.show(
                contents: Self.contents(for: diagnostic),
                anchorRect: windowRect,
                in: window
            )
            return
        }

        guard let delegate else { return }
        guard let range = await identifierRange(at: location) else { return }
        guard !Task.isCancelled else { return }

        guard let info = await delegate.hoverInfo(forRange: range, textView: controller) else { return }
        guard !Task.isCancelled else { return }

        currentRange = range

        let rects = textView.layoutManager.rectsFor(range: range)
        guard let firstRect = rects.first else { return }
        let windowRect = textView.convert(firstRect, to: nil)
        HoverController.shared.show(contents: info.contents, anchorRect: windowRect, in: window)
    }

    private static func contents(for diagnostic: EditorDiagnostic) -> String {
        let title: String
        switch diagnostic.severity {
        case .error: title = "Error"
        case .warning: title = "Warning"
        case .info: title = "Info"
        case .hint: title = "Hint"
        }
        return "\(title): \(diagnostic.message)"
    }

    private func identifierRange(at location: Int) async -> NSRange? {
        let identifierNodeTypes: Set<String> = ["name", "variable_name", "qualified_name", "relative_name"]
        if let nodes = treeSitterClient?.syncNodes(at: location),
           let node = nodes.first(where: { result in
               guard let type = result.node.nodeType else { return false }
               return type.contains("identifier") || identifierNodeTypes.contains(type)
           }) {
            return node.node.range
        }
        return controller?.textIdentifierRange(at: location)
    }

    func cancel() {
        hoverTask?.cancel()
        hoverTask = nil
        currentRange = nil
        HoverController.shared.close()
    }
}