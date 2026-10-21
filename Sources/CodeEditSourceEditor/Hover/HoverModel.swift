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
    private var dismissalTask: Task<Void, Never>?
    private var currentRange: NSRange?
    private var anchorScreenRect: NSRect?

    private static let dwell: Duration = .milliseconds(350)
    private static let dismissalGrace: TimeInterval = 0.2
    private static let pointerPollInterval: Duration = .milliseconds(50)

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

        clearStaleStateIfNeeded()
        let textViewCoords = textView.convert(windowCoordinates, from: nil)
        guard let location = textView.layoutManager.textOffsetAtPoint(textViewCoords),
              location < textView.textStorage.length else {
            hoverTask?.cancel()
            if currentRange != nil || HoverController.shared.isShowing {
                ensurePointerWatch()
            }
            return
        }

        let screenPoint = textView.window?.convertPoint(toScreen: windowCoordinates) ?? NSEvent.mouseLocation

        if HoverController.shared.contains(screenPoint: screenPoint) {
            return
        }

        // Still inside the currently hovered identifier: keep the tooltip.
        if let currentRange, currentRange.contains(location) {
            return
        }

        hoverTask?.cancel()
        if currentRange != nil || HoverController.shared.isShowing {
            ensurePointerWatch()
        }
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
            anchorScreenRect = window.convertToScreen(windowRect)
            HoverController.shared.show(
                content: Self.content(for: diagnostic),
                theme: controller.theme,
                anchorRect: windowRect,
                in: window
            )
            ensurePointerWatch()
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
        anchorScreenRect = window.convertToScreen(windowRect)
        HoverController.shared.show(
            content: info.content,
            theme: controller.theme,
            anchorRect: windowRect,
            in: window
        )
        ensurePointerWatch()
    }

    private static func content(for diagnostic: EditorDiagnostic) -> HoverContent {
        let title: String
        let tone: HoverTone
        let symbol: String
        switch diagnostic.severity {
        case .error:
            title = "Error"
            tone = .error
            symbol = "xmark.octagon.fill"
        case .warning:
            title = "Warning"
            tone = .warning
            symbol = "exclamationmark.triangle.fill"
        case .info:
            title = "Info"
            tone = .info
            symbol = "info.circle.fill"
        case .hint:
            title = "Hint"
            tone = .info
            symbol = "lightbulb.fill"
        }

        var subtitleParts: [String] = []
        if let line = diagnostic.line {
            subtitleParts.append("Line \(line)")
        }
        if let ruleID = diagnostic.ruleID, !ruleID.isEmpty {
            subtitleParts.append(ruleID)
        }

        return .document(HoverDocument(
            header: HoverHeader(
                title: title,
                subtitle: subtitleParts.isEmpty ? nil : subtitleParts.joined(separator: " · "),
                systemImageName: symbol,
                tone: tone
            ),
            blocks: [
                .notice(HoverNotice(message: diagnostic.message, tone: tone))
            ]
        ))
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
        closeCard()
    }

    private func ensurePointerWatch() {
        guard dismissalTask == nil else { return }
        dismissalTask = Task { [weak self] in
            var outsideSince: Date?
            while !Task.isCancelled {
                guard let self else { return }
                guard HoverController.shared.isShowing else {
                    self.closeCard()
                    return
                }
                let pointer = NSEvent.mouseLocation
                let isInside = HoverController.shared.contains(screenPoint: pointer)
                    || (self.anchorScreenRect?.contains(pointer) ?? false)

                if isInside {
                    outsideSince = nil
                } else if let outsideSince {
                    if Date().timeIntervalSince(outsideSince) >= Self.dismissalGrace {
                        self.closeCard()
                        return
                    }
                } else {
                    outsideSince = Date()
                }

                try? await Task.sleep(for: Self.pointerPollInterval)
            }
        }
    }

    private func clearStaleStateIfNeeded() {
        guard !HoverController.shared.isShowing,
              currentRange != nil || anchorScreenRect != nil || dismissalTask != nil else { return }
        dismissalTask?.cancel()
        dismissalTask = nil
        currentRange = nil
        anchorScreenRect = nil
    }

    private func closeCard() {
        dismissalTask?.cancel()
        dismissalTask = nil
        currentRange = nil
        anchorScreenRect = nil
        HoverController.shared.close()
    }
}
