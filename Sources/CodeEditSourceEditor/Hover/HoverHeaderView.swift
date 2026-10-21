//
//  HoverHeaderView.swift
//  CodeEditSourceEditor
//

import AppKit

/// The header row of a hover card: icon, title, subtitle, and badges.
@MainActor
final class HoverHeaderView: NSView {
    private static let iconSize: CGFloat = 16
    private static let badgeSpacing: CGFloat = 4

    init(header: HoverHeader) {
        super.init(frame: .zero)

        let stack = makeStack()
        if let icon = makeIcon(for: header) {
            stack.addArrangedSubview(icon)
        }
        stack.addArrangedSubview(makeTextStack(for: header))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)

        if let badges = makeBadges(for: header) {
            stack.addArrangedSubview(badges)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func naturalWidth(for header: HoverHeader) -> CGFloat {
        let titleWidth = (header.title as NSString).size(
            withAttributes: [.font: HoverContentRenderer.titleFont]
        ).width
        let subtitleWidth = (header.subtitle as NSString?)?.size(
            withAttributes: [.font: HoverContentRenderer.captionFont]
        ).width ?? 0
        var width = max(titleWidth, subtitleWidth)

        if header.systemImageName != nil {
            width += iconSize + 8
        }

        let visibleBadges = visibleBadges(for: header)
        if !visibleBadges.isEmpty {
            let badgesWidth = visibleBadges.reduce(0) { $0 + HoverBadgeView.naturalWidth(for: $1) }
                + CGFloat(visibleBadges.count - 1) * badgeSpacing
            width += 8 + badgesWidth
        }

        return ceil(width)
    }

    static func height(for header: HoverHeader, width: CGFloat) -> CGFloat {
        let view = HoverHeaderView(header: header)
        view.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        view.layoutSubtreeIfNeeded()
        return max(iconSize, ceil(view.fittingSize.height))
    }

    private func makeStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        return stack
    }

    private func makeIcon(for header: HoverHeader) -> NSImageView? {
        guard let symbolName = header.systemImageName,
              let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return nil
        }
        let imageView = NSImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentTintColor = header.tone.color
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: Self.iconSize),
            imageView.heightAnchor.constraint(equalToConstant: Self.iconSize)
        ])
        return imageView
    }

    private func makeTextStack(for header: HoverHeader) -> NSStackView {
        let textStack = NSStackView()
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let titleLabel = NSTextField(labelWithString: header.title)
        titleLabel.font = HoverContentRenderer.titleFont
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStack.addArrangedSubview(titleLabel)

        if let subtitle = header.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !subtitle.isEmpty {
            let subtitleLabel = NSTextField(labelWithString: subtitle)
            subtitleLabel.font = HoverContentRenderer.captionFont
            subtitleLabel.textColor = .secondaryLabelColor
            subtitleLabel.lineBreakMode = .byTruncatingTail
            subtitleLabel.maximumNumberOfLines = 2
            subtitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textStack.addArrangedSubview(subtitleLabel)
        }
        return textStack
    }

    private func makeBadges(for header: HoverHeader) -> NSStackView? {
        let visibleBadges = Self.visibleBadges(for: header)
        guard !visibleBadges.isEmpty else { return nil }
        let badges = NSStackView(views: visibleBadges.map { HoverBadgeView(badge: $0) })
        badges.orientation = .horizontal
        badges.alignment = .centerY
        badges.spacing = Self.badgeSpacing
        badges.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return badges
    }

    private static func visibleBadges(for header: HoverHeader) -> [HoverBadge] {
        header.badges.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// A rounded, tinted badge shown in a hover header.
@MainActor
private final class HoverBadgeView: NSView {
    private let tone: HoverTone
    private let label: NSTextField

    init(badge: HoverBadge) {
        self.tone = badge.tone
        self.label = NSTextField(labelWithString: badge.text)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.masksToBounds = true

        label.font = HoverContentRenderer.badgeFont
        label.textColor = badge.tone.color
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 17)
        ])
        updateBackground()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: ceil(label.intrinsicContentSize.width) + 10,
            height: 17
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    static func naturalWidth(for badge: HoverBadge) -> CGFloat {
        let textWidth = (badge.text as NSString).size(
            withAttributes: [.font: HoverContentRenderer.badgeFont]
        ).width
        return ceil(textWidth) + 10
    }

    private func updateBackground() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = tone.color.withAlphaComponent(0.14).cgColor
        }
    }
}
