//
//  TextViewController+Emmet.swift
//  CodeEditSourceEditor
//

import AppKit
import CodeEditTextView

extension TextViewController {
    /// Expands the Emmet abbreviation immediately before the cursor (e.g. `ul>li*3`) into markup.
    public func expandEmmetAbbreviation() {
        guard let textView else { return }
        let cursor = textView.selectionManager.textSelections.first?.range.location ?? 0
        guard let range = abbreviationRange(before: cursor, in: textView),
              let abbreviation = (textView.textStorage.string as NSString).substring(with: range) as String?,
              let snippet = EmmetExpander.snippet(for: abbreviation) else {
            return
        }
        insertSnippet(snippet, replacing: range)
    }

    /// Wraps each selection with `open`/`close`, keeping the original text selected.
    public func surroundSelection(open: String, close: String) {
        guard let textView else { return }
        let ranges = textView.selectionManager.textSelections
            .map(\.range)
            .sorted { $0.location > $1.location }
        guard !ranges.isEmpty else { return }

        let openLength = (open as NSString).length
        var newSelections: [NSRange] = []
        for range in ranges {
            let selected = (textView.textStorage.string as NSString).substring(with: range)
            textView.replaceCharacters(in: range, with: open + selected + close)
            newSelections.append(NSRange(location: range.location + openLength, length: (selected as NSString).length))
        }
        textView.selectionManager.setSelectedRanges(newSelections)
    }

    /// The run of Emmet abbreviation characters immediately before `location`.
    private func abbreviationRange(before location: Int, in textView: TextView) -> NSRange? {
        let ns = textView.textStorage.string as NSString
        let limit = min(max(location, 0), ns.length)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.#>*{}[]-_:$")
        var start = limit
        while start > 0 {
            let character = ns.character(at: start - 1)
            guard let scalar = UnicodeScalar(character), allowed.contains(scalar) else { break }
            start -= 1
        }
        guard start < limit else { return nil }
        return NSRange(location: start, length: limit - start)
    }
}
