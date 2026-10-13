//
//  TextViewController+IdentifierRange.swift
//  CodeEditSourceEditor
//

import AppKit

extension TextViewController {
    /// Returns the range of the identifier-like token at (or immediately before) the given
    /// UTF-16 offset, derived from the text alone.
    ///
    /// This is a reliable fallback for hover and cmd+click hit-testing when tree-sitter node
    /// lookups are unavailable. Expands over `[A-Za-z0-9_\$]`.
    func textIdentifierRange(at offset: Int) -> NSRange? {
        guard let textView else { return nil }
        let text = textView.string as NSString
        guard text.length > 0 else { return nil }

        func isIdentifier(_ char: unichar) -> Bool {
            guard let scalar = UnicodeScalar(char) else { return false }
            return CharacterSet.alphanumerics.contains(scalar)
                || scalar == "_" || scalar == "\\" || scalar == "$"
        }

        var location = min(max(offset, 0), text.length - 1)

        // If the offset lands just past a word, step back onto it.
        if location > 0, !isIdentifier(text.character(at: location)),
           isIdentifier(text.character(at: location - 1)) {
            location -= 1
        }
        guard isIdentifier(text.character(at: location)) else { return nil }

        var start = location
        while start > 0, isIdentifier(text.character(at: start - 1)) {
            start -= 1
        }
        var end = location
        while end < text.length, isIdentifier(text.character(at: end)) {
            end += 1
        }
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }
}