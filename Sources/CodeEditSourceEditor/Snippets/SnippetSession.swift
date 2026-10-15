//
//  SnippetSession.swift
//  CodeEditSourceEditor
//

import AppKit
import CodeEditTextView

/// Tracks an active snippet insertion: its tab stops and the current stop.
///
/// Mirrors (the same index used more than once) are handled by selecting every range of the active index
/// at once — the editor is multi-cursor, so typing updates all of them together.
@MainActor
final class SnippetSession {
    struct Stop {
        let index: Int
        var range: NSRange
    }

    private(set) var stops: [Stop]
    /// Distinct stop indices in navigation order (the final `0` stop last).
    private let order: [Int]
    private(set) var position: Int = 0

    init(parsed: ParsedSnippet, startLocation: Int) {
        stops = parsed.stops.map {
            Stop(
                index: $0.index,
                range: NSRange(location: $0.range.location + startLocation, length: $0.range.length)
            )
        }
        var indices = Set(stops.map(\.index))
        indices.remove(0)
        order = indices.sorted() + [0]
    }

    /// The ranges to select for the current stop (more than one when the index is mirrored).
    var activeRanges: [NSRange] {
        guard position < order.count else { return [] }
        return stops.filter { $0.index == order[position] }.map(\.range)
    }

    var isAtLastStop: Bool { position >= order.count - 1 }

    @discardableResult
    func moveNext() -> Bool {
        guard position + 1 < order.count else { return false }
        position += 1
        return true
    }

    @discardableResult
    func movePrevious() -> Bool {
        guard position > 0 else { return false }
        position -= 1
        return true
    }

    /// Re-bases stop ranges after an edit, mirroring `TextSelectionManager.didReplaceCharacters`.
    func updateAfterEdit(range: NSRange, delta: Int) {
        for index in stops.indices {
            let stopRange = stops[index].range
            if stopRange.location >= range.max {
                stops[index].range.location = max(0, stopRange.location + delta)
            } else if NSMaxRange(stopRange) <= range.location {
                // Entirely before the edit — unchanged.
            } else {
                stops[index].range = NSRange(location: range.location + max(0, delta), length: 0)
            }
        }
    }
}

extension TextViewController {
    /// Replaces `range` with the given (LSP) snippet and starts a snippet session with tab stops.
    public func insertSnippet(_ snippet: String, replacing range: NSRange) {
        guard let textView else { return }
        let parsed = SnippetParser.parse(snippet)
        textView.replaceCharacters(in: range, with: parsed.text)
        snippetSession = SnippetSession(parsed: parsed, startLocation: range.location)
        applyActiveSnippetSelection()
    }

    /// Ends the active snippet session, if any.
    public func endSnippetSession() {
        snippetSession = nil
    }

    /// Moves to the next/previous snippet stop. Returns `true` if a session handled the key.
    @discardableResult
    func snippetTab(backwards: Bool) -> Bool {
        guard let session = snippetSession else { return false }
        let moved = backwards ? session.movePrevious() : session.moveNext()
        if !moved {
            if !backwards {
                endSnippetSession()
            }
            return true
        }
        applyActiveSnippetSelection()
        return true
    }

    private func applyActiveSnippetSelection() {
        guard let session = snippetSession, let textView else { return }
        let length = textView.textStorage.length
        let ranges = session.activeRanges.filter { $0.location >= 0 && NSMaxRange($0) <= length }
        guard !ranges.isEmpty else { return }
        textView.selectionManager.setSelectedRanges(ranges)
        if let first = ranges.first {
            textView.scrollToRange(first, center: false)
        }
    }
}
