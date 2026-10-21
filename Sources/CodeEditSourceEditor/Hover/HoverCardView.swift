//
//  HoverCardView.swift
//  CodeEditSourceEditor
//

import AppKit

/// The visual card presented for a hover.
@MainActor
final class HoverCardView: NSVisualEffectView {
    static let minWidth: CGFloat = 260
    static let maxWidth: CGFloat = 520
    static let maxHeight: CGFloat = 420
    static let inset: CGFloat = 12
    static let spacing: CGFloat = 10
    static let cornerRadius: CGFloat = 8

    let preferredSize: NSSize

    private struct Layout {
        let header: HoverHeader?
        let attributedContent: NSAttributedString
        let size: NSSize
        let contentWidth: CGFloat
        let contentHeight: CGFloat
        let viewportHeight: CGFloat
        let hasHeader: Bool
        let hasContent: Bool
    }

    init(
        content: HoverContent,
        theme: EditorTheme? = nil,
        maxWidth: CGFloat = HoverCardView.maxWidth
    ) {
        let layout = Self.layout(for: content, theme: theme, maxWidth: maxWidth)
        self.preferredSize = layout.size

        super.init(frame: NSRect(origin: .zero, size: layout.size))

        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = Self.spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.inset),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: Self.inset),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.inset)
        ])

        if let header = layout.header {
            stack.addArrangedSubview(HoverHeaderView(header: header))
        }

        if layout.hasHeader, layout.hasContent {
            let separator = NSBox()
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
            stack.addArrangedSubview(separator)
        }

        if layout.hasContent {
            let scrollView = Self.makeScrollView(
                attributed: layout.attributedContent,
                width: layout.contentWidth,
                contentHeight: layout.contentHeight,
                viewportHeight: layout.viewportHeight
            )
            scrollView.heightAnchor.constraint(equalToConstant: layout.viewportHeight).isActive = true
            stack.addArrangedSubview(scrollView)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func layout(
        for content: HoverContent,
        theme: EditorTheme?,
        maxWidth: CGFloat
    ) -> Layout {
        let header: HoverHeader?
        let blocks: [HoverBlock]
        let attributedContent: NSAttributedString

        switch content {
        case .plainText, .markdown:
            header = nil
            blocks = []
            attributedContent = HoverContentRenderer.attributedString(for: content, theme: theme)
        case .document(let document):
            header = document.header
            blocks = document.blocks
            attributedContent = HoverContentRenderer.attributedString(for: blocks, theme: theme)
        }

        let headerNaturalWidth = header.map(HoverHeaderView.naturalWidth) ?? 0
        let contentNaturalWidth = blocks.isEmpty
            ? ceil(attributedContent.size().width)
            : HoverContentRenderer.naturalWidth(for: blocks, theme: theme)
        let naturalWidth = max(headerNaturalWidth, contentNaturalWidth)
        let width = min(maxWidth, max(minWidth, ceil(naturalWidth) + inset * 2))
        let contentWidth = max(1, width - inset * 2)

        let hasHeader = header != nil
        let hasContent = attributedContent.length > 0
        let headerHeight = header.map { HoverHeaderView.height(for: $0, width: contentWidth) } ?? 0
        let contentHeight = hasContent
            ? HoverContentRenderer.height(of: attributedContent, width: contentWidth)
            : 0

        let separatorHeight: CGFloat = hasHeader && hasContent ? 1 : 0
        let separatorSpacing: CGFloat = hasHeader && hasContent ? spacing * 2 : 0
        let availableContentHeight = max(
            1,
            maxHeight - inset * 2 - headerHeight - separatorHeight - separatorSpacing
        )
        let viewportHeight = hasContent ? min(contentHeight, availableContentHeight) : 0
        let height = inset * 2 + headerHeight + separatorSpacing + separatorHeight + viewportHeight

        return Layout(
            header: header,
            attributedContent: attributedContent,
            size: NSSize(width: ceil(width), height: ceil(height)),
            contentWidth: contentWidth,
            contentHeight: contentHeight,
            viewportHeight: viewportHeight,
            hasHeader: hasHeader,
            hasContent: hasContent
        )
    }

    private static func makeScrollView(
        attributed: NSAttributedString,
        width: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat
    ) -> NSScrollView {
        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            containerSize: NSSize(width: width, height: .greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        let textView = NSTextView(
            frame: NSRect(x: 0, y: 0, width: width, height: max(contentHeight, viewportHeight)),
            textContainer: textContainer
        )
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: width, height: 0)
        textView.maxSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.controlAccentColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = textView
        return scrollView
    }
}
