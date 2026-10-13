//
//  HoverModel.swift
//  CodeEditSourceEditor
//

import AppKit
import CodeEditTextView
import os

/// Manages hover detection: after the mouse rests over an identifier for a short dwell
/// period, it asks the ``HoverDelegate`` for content and presents a tooltip.
@MainActor
final class HoverModel {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CodeEdit",
        category: "Hover"
    )

    weak var delegate: HoverDelegate?
    weak var treeSitterClient: TreeSitterClient?
    weak var controller: TextViewController?

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
        guard delegate != nil, let controller, let textView = controller.textView else {
            Self.logger.debug("hover skipped: no delegate/controller/textView")
            cancel()
            return
        }

        let textViewCoords = textView.convert(windowCoordinates, from: nil)
        guard let location = textView.layoutManager.textOffsetAtPoint(textViewCoords),
              location < textView.textStorage.length else {
            Self.logger.debug("hover skipped: no offset at point")
            cancel()
            return
        }
        Self.logger.debug("hover mouseMoved offset=\(location, privacy: .public)")

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
        guard let controller, let delegate, let textView = controller.textView,
              let window = controller.view.window else { return }

        guard let range = await identifierRange(at: location) else {
            Self.logger.notice("hover: no identifier range at offset=\(location, privacy: .public)")
            return
        }
        guard !Task.isCancelled else { return }

        let identifier = (textView.string as NSString).substring(with: range)
        Self.logger.notice(
            "hover: identifier='\(identifier, privacy: .public)' range=\(NSStringFromRange(range), privacy: .public)"
        )

        guard let info = await delegate.hoverInfo(forRange: range, textView: controller) else {
            Self.logger.notice("hover: delegate returned nil for '\(identifier, privacy: .public)'")
            return
        }
        guard !Task.isCancelled else { return }
        Self.logger.notice(
            "hover: showing tooltip (\(info.contents.count, privacy: .public) chars) for '\(identifier, privacy: .public)'"
        )

        currentRange = range

        let rects = textView.layoutManager.rectsFor(range: range)
        guard let firstRect = rects.first else { return }
        let windowRect = textView.convert(firstRect, to: nil)
        HoverController.shared.show(contents: info.contents, anchorRect: windowRect, in: window)
    }

    private func identifierRange(at location: Int) async -> NSRange? {
        let identifierNodeTypes: Set<String> = ["name", "variable_name", "qualified_name", "relative_name"]
        guard let nodes = treeSitterClient?.syncNodes(at: location) else {
            Self.logger.notice("hover: no tree-sitter nodes at offset=\(location, privacy: .public) (falling back to text)")
            return textFallbackRange(at: location)
        }
        let nodeTypes = nodes.map { $0.node.nodeType ?? "?" }
        Self.logger.notice("hover: nodes at \(location, privacy: .public): \(nodeTypes, privacy: .public)")
        guard let node = nodes.first(where: { result in
            guard let type = result.node.nodeType else { return false }
            return type.contains("identifier") || identifierNodeTypes.contains(type)
        }) else {
            Self.logger.notice("hover: no identifier-like node at offset=\(location, privacy: .public) (falling back to text)")
            return textFallbackRange(at: location)
        }
        return node.node.range
    }

    private func textFallbackRange(at location: Int) -> NSRange? {
        guard let range = controller?.textIdentifierRange(at: location) else { return nil }
        Self.logger.notice("hover: text fallback range=\(NSStringFromRange(range), privacy: .public)")
        return range
    }

    func cancel() {
        hoverTask?.cancel()
        hoverTask = nil
        currentRange = nil
        HoverController.shared.close()
    }
}