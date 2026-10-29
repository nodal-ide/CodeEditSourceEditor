//
//  TextViewController+FindPanelTarget.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 3/16/25.
//

import AppKit
import CodeEditTextView

extension TextViewController: FindPanelTarget {
    var findPanelTargetView: NSView {
        textView
    }

    func findPanelWillShow(panelHeight: CGFloat) {
        updateContentInsets()
    }

    func findPanelWillHide(panelHeight: CGFloat) {
        updateContentInsets()
    }

    func findPanelModeDidChange(to mode: FindPanelMode) {
        updateContentInsets()
    }

    var emphasisManager: EmphasisManager? {
        textView?.emphasisManager
    }
}

// MARK: - Find Panel Actions

extension TextViewController {
    /// Handles AppKit find panel actions (`⌘F`, `⌥⌘F`, `⌘G`, `⇧⌘G`, `⌘E`).
    ///
    /// `TextView` is not an `NSTextView` and owns no find panel, so nothing in the editor currently answers
    /// `performFindPanelAction(_:)`. Implementing it here puts the controller in the responder chain and lets
    /// the app's Find menu drive the built-in panel.
    @objc public func performFindPanelAction(_ sender: Any?) {
        guard let findViewController, let action = Self.findPanelAction(from: sender) else { return }
        let viewModel = findViewController.viewModel

        switch action {
        case .showFindPanel:
            findViewController.showFindPanel()
        case .replace, .replaceAndFind, .replaceAll:
            // The panel owns the replacement UI; open it with the replacement field visible.
            findViewController.showFindPanel()
            viewModel.mode = .replace
        case .next, .previous:
            if !viewModel.isShowingFindPanel, !viewModel.findText.isEmpty {
                findViewController.showFindPanel()
            }
            if action == .next {
                viewModel.moveToNextMatch()
            } else {
                viewModel.moveToPreviousMatch()
            }
        case .setFindString:
            guard let string = selectedFindString else { return }
            viewModel.findText = string
            findViewController.showFindPanel()
        default:
            break
        }
    }

    /// `⌘J` — jumps to the current selection and centers it in the viewport.
    ///
    /// Deliberately not named `centerSelectionInVisibleArea(_:)`: `NSResponder` already declares that selector with
    /// a no-op default, so the text view answers it before this controller is reached.
    @objc public func centerSelectionInViewport(_ sender: Any?) {
        guard let textView else { return }
        let range = textView.selectedRange
        guard range.location <= (textView.textStorage?.length ?? 0) else { return }
        textView.scrollToRange(range, center: true)
    }

    /// Find actions arrive as a menu item (tag) or as an action enum bridged to a number.
    private static func findPanelAction(from sender: Any?) -> NSFindPanelAction? {
        let rawValue: UInt?
        switch sender {
        case let item as NSMenuItem:
            rawValue = UInt(item.tag)
        case let number as NSNumber:
            rawValue = number.uintValue
        default:
            rawValue = nil
        }
        return rawValue.flatMap(NSFindPanelAction.init(rawValue:))
    }

    /// The current selection when it is usable as a find query.
    private var selectedFindString: String? {
        guard let textView else { return nil }
        let range = textView.selectedRange
        guard range.length > 0, let string = textView.substring(from: range) else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
