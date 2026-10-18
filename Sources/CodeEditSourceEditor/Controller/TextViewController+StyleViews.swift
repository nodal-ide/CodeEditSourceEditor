//
//  TextViewController+StyleViews.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 7/3/24.
//

import AppKit
import CodeEditTextView

extension TextViewController {
    package func generateParagraphStyle() -> NSMutableParagraphStyle {
        // swiftlint:disable:next force_cast
        let paragraph = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraph.tabStops.removeAll()
        paragraph.defaultTabInterval = CGFloat(tabWidth) * font.charWidth
        return paragraph
    }

    /// Style the text view.
    package func styleTextView() {
        textView.postsFrameChangedNotifications = true
        textView.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Style the scroll view.
    package func styleScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView.postsFrameChangedNotifications = true
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
    }

    /// Updates all relevant content insets including the find panel, scroll view and gutter position.
    package func updateContentInsets() {
        updateTextInsets()

        scrollView.contentView.postsBoundsChangedNotifications = true
        if let contentInsets = configuration.layout.contentInsets {
            scrollView.automaticallyAdjustsContentInsets = false
            scrollView.contentInsets = contentInsets
        } else {
            scrollView.automaticallyAdjustsContentInsets = true
        }

        // `additionalTextInsets` only effects text content.
        let additionalTextInsets = configuration.layout.additionalTextInsets
        scrollView.contentInsets.top += additionalTextInsets?.top ?? 0
        scrollView.contentInsets.bottom += additionalTextInsets?.bottom ?? 0

        // Inset the top by the find panel height
        let findInset: CGFloat = if findViewController?.viewModel.isShowingFindPanel ?? false {
            findViewController?.viewModel.panelHeight ?? 0
        } else {
            0
        }
        scrollView.contentInsets.top += findInset

        findViewController?.topPadding = configuration.layout.contentInsets?.top

        gutterView.frame.origin.y = textView.frame.origin.y - scrollView.contentInsets.top

        // Update scrollview tiling
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Updates the text view's text insets. See ``textViewInsets`` for calculation.
    func updateTextInsets() {
        // Allow this method to be called before ``loadView()``
        guard textView != nil, gutterView != nil else { return }
        if textView.textInsets != textViewInsets {
            textView.textInsets = textViewInsets
        }
    }
}
