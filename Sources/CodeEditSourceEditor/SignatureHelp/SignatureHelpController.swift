//
//  SignatureHelpController.swift
//  CodeEditSourceEditor
//

import AppKit

/// Presents a lightweight, non-activating panel showing a call signature with the active
/// parameter emphasized.
@MainActor
final class SignatureHelpController {
    static let shared = SignatureHelpController()

    private var panel: NSPanel?
    private let maxWidth: CGFloat = 620
    private let padding: CGFloat = 10

    private init() {}

    func show(info: SignatureHelpInfo, anchorRect: NSRect, in parentWindow: NSWindow) {
        let attributed = Self.attributed(info)
        let bounding = attributed.boundingRect(
            with: NSSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let size = NSSize(
            width: min(maxWidth, ceil(bounding.width)) + padding * 2,
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
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = effect

        // Position below the anchor rect, in screen coordinates.
        let screenRect = parentWindow.convertToScreen(anchorRect)
        var origin = NSPoint(x: screenRect.minX, y: screenRect.minY - size.height - 6)
        if let screen = parentWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)
            if origin.y < visible.minY {
                origin.y = screenRect.maxY + 6
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

    private static func attributed(_ info: SignatureHelpInfo) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let result = NSMutableAttributedString(
            string: info.signature,
            attributes: [
                .font: mono,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph
            ]
        )
        // Emphasize the active parameter inside the signature, if present.
        if info.activeParameter >= 0, info.activeParameter < info.parameters.count {
            let parameter = info.parameters[info.activeParameter]
            let range = (info.signature as NSString).range(of: parameter)
            if range.location != NSNotFound {
                result.addAttributes(
                    [
                        .backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.25),
                        .foregroundColor: NSColor.controlAccentColor,
                        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
                    ],
                    range: range
                )
            }
        }
        return result
    }
}