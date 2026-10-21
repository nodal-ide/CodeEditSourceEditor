//
//  HoverController.swift
//  CodeEditSourceEditor
//

import AppKit

/// Presents a lightweight, non-activating tooltip panel for hover information.
@MainActor
final class HoverController {
    static let shared = HoverController()

    private var panel: HoverPanel?
    private var resignObserver: NSObjectProtocol?
    private var closeObserver: NSObjectProtocol?
    private var panelResignObserver: NSObjectProtocol?
    private var deactivateObserver: NSObjectProtocol?

    private init() {}

    /// Shows the card near the given rect (in the parent window's coordinate space).
    func show(
        content: HoverContent,
        theme: EditorTheme? = nil,
        anchorRect: NSRect,
        in parentWindow: NSWindow
    ) {
        guard !content.isEmpty else {
            close()
            return
        }

        let card = HoverCardView(content: content, theme: theme)
        let size = card.preferredSize

        let panel = HoverPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.onDismiss = { [weak self] in
            self?.close()
        }
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
        observeParentWindow(parentWindow)
        observePanel(panel)
        observeApplication()
        panel.orderFront(nil)
    }

    func contains(screenPoint: NSPoint) -> Bool {
        panel?.frame.contains(screenPoint) ?? false
    }

    var isShowing: Bool {
        panel != nil
    }

    func close() {
        removeObservers()
        panel?.orderOut(nil)
        panel = nil
    }

    private func observeParentWindow(_ window: NSWindow) {
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let panel = self.panel, !panel.isKeyWindow else { return }
                self.close()
            }
        }
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }
    }

    private func observePanel(_ panel: NSPanel) {
        panelResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }
    }

    private func observeApplication() {
        deactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApplication.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.close()
            }
        }
    }

    private func removeObservers() {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        if let panelResignObserver {
            NotificationCenter.default.removeObserver(panelResignObserver)
            self.panelResignObserver = nil
        }
        if let deactivateObserver {
            NotificationCenter.default.removeObserver(deactivateObserver)
            self.deactivateObserver = nil
        }
    }
}

private final class HoverPanel: NSPanel {
    var onDismiss: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onDismiss?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onDismiss?()
            return
        }
        super.keyDown(with: event)
    }
}
