//
//  HoverController.swift
//  CodeEditSourceEditor
//

import AppKit

/// Presents a lightweight, non-activating tooltip panel for hover information.
@MainActor
final class HoverController {
    static let shared = HoverController()

    private var panel: NSPanel?

    private init() {}

    /// Shows the card near the given rect (in the parent window's coordinate space).
    func show(content: HoverContent, anchorRect: NSRect, in parentWindow: NSWindow) {
        guard !content.isEmpty else {
            close()
            return
        }

        let card = HoverCardView(content: content)
        let size = card.preferredSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.contentView = card

        let screenRect = parentWindow.convertToScreen(anchorRect)
        var origin = NSPoint(x: screenRect.minX, y: screenRect.maxY + 6)
        if let screen = parentWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            if origin.y + size.height > visible.maxY {
                origin.y = screenRect.minY - size.height - 6
            }
            origin.y = min(max(origin.y, visible.minY + 4), visible.maxY - size.height - 4)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: false)

        close()
        self.panel = panel
        panel.orderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
