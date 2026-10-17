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
    private let maxWidth: CGFloat = 460
    private let padding: CGFloat = 10

    private init() {}

    /// Shows the tooltip near the given rect (in the parent window's coordinate space).
    func show(contents: String, anchorRect: NSRect, in parentWindow: NSWindow) {
        let attributed = Self.attributed(contents)
        let bounding = attributed.boundingRect(
            with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let size = NSSize(
            width: ceil(bounding.width) + padding * 2,
            height: ceil(bounding.height) + padding * 2
        )

        let textField = NSTextField(labelWithAttributedString: attributed)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.preferredMaxLayoutWidth = maxWidth
        textField.maximumNumberOfLines = 0
        textField.lineBreakMode = .byWordWrapping
        textField.isSelectable = true

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 6
        effect.layer?.masksToBounds = true
        effect.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: padding),
            textField.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -padding),
            textField.topAnchor.constraint(equalTo: effect.topAnchor, constant: padding),
            textField.bottomAnchor.constraint(equalTo: effect.bottomAnchor, constant: -padding)
        ])

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
        panel.contentView = effect

        // Position above the anchor rect, in screen coordinates.
        let screenRect = parentWindow.convertToScreen(anchorRect)
        var origin = NSPoint(x: screenRect.minX, y: screenRect.maxY + 6)
        if let screen = parentWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            if origin.y + size.height > visible.maxY {
                origin.y = screenRect.minY - size.height - 6
            }
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

    private static func attributed(_ contents: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(
            string: contents,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        )
    }
}