//
//  SuggestionController+Window.swift
//  CodeEditTextView
//
//  Created by Abe Malla on 12/22/24.
//

import AppKit

/// A non-activating panel that can become key (so keyboard navigation works).
final class SuggestionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

extension SuggestionController {
    /// Positions the suggestion window near the cursor, clamped to the visible screen.
    public func constrainWindowToScreenEdges(cursorRect: NSRect, font: NSFont) {
        guard let window = self.window else { return }
        guard let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }

        let size = window.frame.size
        let padding: CGFloat = 6
        let minY = screenFrame.minY + padding
        let maxY = max(minY, screenFrame.maxY - size.height - padding)

        // Prefer below the cursor; flip above when there isn't room.
        var originY = cursorRect.minY - size.height - padding
        if originY < minY {
            originY = cursorRect.maxY + padding
            isWindowAboveCursor = true
        } else {
            isWindowAboveCursor = false
        }
        originY = min(max(originY, minY), maxY)

        // Align with the cursor's left edge, clamped horizontally.
        let minX = screenFrame.minX + padding
        let maxX = max(minX, screenFrame.maxX - size.width - padding)
        let originX = min(max(cursorRect.minX, minX), maxX)

        window.setFrameOrigin(NSPoint(x: originX, y: originY))
        print("[suggest] constrainWindow: cursor=\(cursorRect) screen=\(screenFrame) -> origin=(\(originX), \(originY))")
    }

    func updateWindowSize(newSize: NSSize) {
        if let popover {
            popover.contentSize = newSize
            return
        }

        guard let window else { return }
        let oldFrame = window.frame

        window.minSize = newSize
        window.maxSize = NSSize(width: CGFloat.infinity, height: newSize.height)

        window.setContentSize(newSize)

        if isWindowAboveCursor && oldFrame.size.height != newSize.height {
            window.setFrameOrigin(oldFrame.origin)
        }

        // Keep the (resized) popup on-screen.
        if let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame {
            var origin = window.frame.origin
            origin.x = min(max(origin.x, screenFrame.minX + 6), max(screenFrame.minX + 6, screenFrame.maxX - newSize.width - 6))
            origin.y = min(max(origin.y, screenFrame.minY + 6), max(screenFrame.minY + 6, screenFrame.maxY - newSize.height - 6))
            window.setFrameOrigin(origin)
        }
        print("[suggest] updateWindowSize: size=\(newSize) frame=\(window.frame) visible=\(window.isVisible)")
    }

    // MARK: - Private Methods

    static func makeWindow() -> NSWindow {
        // Must be an `NSPanel`: `.nonactivatingPanel`/`.utilityWindow` are panel-only style masks and are
        // rejected on a plain `NSWindow`, leaving the completion popup unable to display. The subclass
        // allows the panel to become key so arrow/enter keys navigate the suggestion list.
        let window = SuggestionPanel(
            contentRect: .zero,
            styleMask: [.resizable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isExcludedFromWindowsMenu = true
        window.isReleasedWhenClosed = false
        window.level = .popUpMenu
        window.hasShadow = true
        window.isOpaque = false
        window.tabbingMode = .disallowed
        window.hidesOnDeactivate = true
        window.backgroundColor = .clear

        return window
    }
}
