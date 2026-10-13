//
//  SignatureHelpModel.swift
//  CodeEditSourceEditor
//

import AppKit
import CodeEditTextView

/// Detects when the cursor is inside a call's argument list and requests signature help
/// from the ``SignatureHelpDelegate``, presenting a small popover.
@MainActor
final class SignatureHelpModel {
    weak var delegate: SignatureHelpDelegate?
    weak var controller: TextViewController?

    private var requestTask: Task<Void, Never>?

    init(controller: TextViewController?, delegate: SignatureHelpDelegate?) {
        self.controller = controller
        self.delegate = delegate
    }

    func selectionUpdated(_ position: CursorPosition) {
        update(at: position.range.location)
    }

    func textDidChange() {
        guard let offset = controller?.cursorPositions.first?.range.location else {
            cancel()
            return
        }
        update(at: offset)
    }

    private func update(at offset: Int) {
        guard delegate != nil, let controller, let textView = controller.textView,
              let context = Self.argumentContext(in: textView.string, at: offset) else {
            cancel()
            return
        }

        // Only one outstanding request at a time.
        requestTask?.cancel()
        requestTask = Task { [weak self] in
            guard let self, let delegate = self.delegate, let controller = self.controller else { return }
            let info = await delegate.signatureHelp(
                calleeRange: context.calleeRange,
                argumentIndex: context.argumentIndex,
                textView: controller
            )
            guard !Task.isCancelled else { return }
            guard let info else {
                self.cancel()
                return
            }
            self.present(info, at: offset)
        }
    }

    private func present(_ info: SignatureHelpInfo, at offset: Int) {
        guard let controller, let textView = controller.textView,
              let window = controller.view.window,
              let rect = textView.layoutManager.rectForOffset(offset) else { return }
        let windowRect = textView.convert(rect, to: nil)
        SignatureHelpController.shared.show(info: info, anchorRect: windowRect, in: window)
    }

    func cancel() {
        requestTask?.cancel()
        requestTask = nil
        SignatureHelpController.shared.close()
    }

    // MARK: - Argument context detection

    struct ArgumentContext {
        let calleeRange: NSRange
        let argumentIndex: Int
    }

    /// Returns the callee identifier range and the current argument index if the offset is
    /// inside a `(...)` argument list; otherwise `nil`.
    static func argumentContext(in text: String, at offset: Int) -> ArgumentContext? {
        let ns = text as NSString
        let safe = min(max(offset, 0), ns.length)

        var depth = 0
        var index = safe - 1
        while index >= 0 {
            let char = ns.character(at: index)
            if char == 0x29 || char == 0x5D || char == 0x7D { // ) ] }
                depth += 1
            } else if char == 0x28 || char == 0x5B || char == 0x7B { // ( [ {
                if depth == 0 {
                    guard char == 0x28 else { return nil } // innermost bracket isn't `(`
                    guard let calleeRange = calleeRange(before: index, in: ns) else { return nil }
                    let argumentIndex = selfArgumentIndex(in: ns, from: index + 1, to: safe)
                    return ArgumentContext(calleeRange: calleeRange, argumentIndex: argumentIndex)
                }
                depth -= 1
            }
            index -= 1
        }
        return nil
    }

    private static func calleeRange(before openParen: Int, in ns: NSString) -> NSRange? {
        var index = openParen - 1
        while index >= 0, isWhitespace(ns.character(at: index)) { index -= 1 }
        let end = index + 1
        while index >= 0, isIdentifierChar(ns.character(at: index)) { index -= 1 }
        let start = index + 1
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private static func selfArgumentIndex(in ns: NSString, from start: Int, to end: Int) -> Int {
        var depth = 0
        var index = 0
        var i = start
        while i < end {
            let char = ns.character(at: i)
            if char == 0x28 || char == 0x5B || char == 0x7B { depth += 1 }
            else if char == 0x29 || char == 0x5D || char == 0x7D { depth -= 1 }
            else if char == 0x2C, depth == 0 { index += 1 } // ,
            i += 1
        }
        return index
    }

    private static func isIdentifierChar(_ char: unichar) -> Bool {
        guard let scalar = UnicodeScalar(char) else { return false }
        return CharacterSet.alphanumerics.contains(scalar)
            || scalar == "_" || scalar == "\\" || scalar == "$"
    }

    private static func isWhitespace(_ char: unichar) -> Bool {
        char == 0x20 || char == 0x09 || char == 0x0A || char == 0x0D
    }
}