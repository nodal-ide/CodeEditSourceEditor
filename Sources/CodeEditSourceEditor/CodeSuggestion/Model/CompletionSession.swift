//
//  CompletionSession.swift
//  CodeEditSourceEditor
//

import Foundation

/// Owns one completion session for a text view: the initial request, instant local filtering of the
/// snapshot, and a debounced, cancellable refresh whose stale responses are dropped.
@MainActor
public final class CompletionSession {
    public enum Update {
        case close
        /// Keep the window open with no rows while a refresh is in flight.
        case pending
        case items([any CodeSuggestionEntry])
    }

    private struct Context {
        let textView: TextViewController
        let delegate: any CodeSuggestionDelegate
    }

    public static let refreshDelay: Duration = .milliseconds(50)
    public static let itemLimit = CompletionMatcher.defaultLimit
    private static let snapshotLimit = 600

    private var context: Context?
    private var snapshot: [any CodeSuggestionEntry] = []
    private var prefixStart = 0
    private var isIncomplete = false
    private var generation = 0
    private var lastRefreshQuery = ""
    private var refreshTask: Task<Void, Never>?

    public var isActive: Bool { context != nil }
    /// Called with a ranked list after a refresh, or `nil` when the refresh produced no results.
    public var onRefresh: (([any CodeSuggestionEntry]?) -> Void)?

    public func open(
        textView: TextViewController,
        delegate: any CodeSuggestionDelegate,
        position: CursorPosition
    ) async -> CompletionResult? {
        cancel()
        let generation = self.generation
        guard let result = await delegate.completionResultRequested(
            textView: textView,
            cursorPosition: position
        ) else {
            return nil
        }
        guard !Task.isCancelled, self.generation == generation else { return nil }

        context = Context(textView: textView, delegate: delegate)
        snapshot = Array(result.items.prefix(Self.snapshotLimit))
        isIncomplete = result.isIncomplete
        prefixStart = Self.prefixStart(in: textView.textView.string, before: position.range.location)
        lastRefreshQuery = Self.query(
            in: textView.textView.string,
            from: prefixStart,
            to: position.range.location
        )
        return CompletionResult(
            items: CompletionMatcher.ranked(snapshot, query: "", limit: Self.itemLimit),
            isIncomplete: result.isIncomplete
        )
    }

    public func update(textView: TextViewController, position: CursorPosition) -> Update {
        guard let context, context.textView === textView else { return .close }
        let cursor = position.range.location
        let text = textView.textView.string as NSString
        guard cursor >= prefixStart, cursor <= text.length else { return .close }

        let query = Self.query(in: textView.textView.string, from: prefixStart, to: cursor)
        guard !query.contains(where: { $0.isWhitespace }) else { return .close }

        let matched = CompletionMatcher.ranked(snapshot, query: query, limit: Self.itemLimit)
        if !matched.isEmpty {
            scheduleRefreshIfNeeded(textView: textView, query: query, cursor: cursor)
            return .items(matched)
        }

        guard context.delegate.supportsCompletionRefresh else { return .close }
        scheduleRefreshIfNeeded(textView: textView, query: query, cursor: cursor)
        return .pending
    }

    public func cancel() {
        generation &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        context = nil
        snapshot = []
        prefixStart = 0
        isIncomplete = false
        lastRefreshQuery = ""
    }

    // MARK: - Refresh

    private func scheduleRefreshIfNeeded(textView: TextViewController, query: String, cursor: Int) {
        guard let delegate = context?.delegate, delegate.supportsCompletionRefresh else { return }
        guard !query.isEmpty || isIncomplete else { return }
        guard query != lastRefreshQuery else { return }

        lastRefreshQuery = query
        let generation = self.generation
        let anchor = prefixStart
        refreshTask?.cancel()
        refreshTask = Task { [weak self, weak textView] in
            try? await Task.sleep(for: Self.refreshDelay)
            guard let self, let textView, !Task.isCancelled, self.generation == generation,
                  let context = self.context, context.textView === textView else {
                return
            }

            let currentCursor = textView.cursorPositions.first?.range.location ?? cursor
            let currentStart = Self.prefixStart(in: textView.textView.string, before: currentCursor)
            guard currentStart >= anchor else {
                self.onRefresh?(nil)
                return
            }

            guard let result = await context.delegate.completionRefreshRequested(
                textView: textView,
                cursorPosition: CursorPosition(range: NSRange(location: currentCursor, length: 0))
            ) else {
                guard !Task.isCancelled else { return }
                self.onRefresh?(nil)
                return
            }
            guard !Task.isCancelled, self.generation == generation, self.context?.textView === textView else {
                return
            }

            self.prefixStart = currentStart
            self.snapshot = Array(result.items.prefix(Self.snapshotLimit))
            self.isIncomplete = result.isIncomplete
            let currentQuery = Self.query(
                in: textView.textView.string,
                from: currentStart,
                to: currentCursor
            )
            self.lastRefreshQuery = currentQuery
            let ranked = CompletionMatcher.ranked(
                self.snapshot,
                query: currentQuery,
                limit: Self.itemLimit
            )
            self.onRefresh?(ranked.isEmpty ? nil : ranked)
        }
    }

    // MARK: - Text helpers

    nonisolated static func prefixStart(in text: String, before offset: Int) -> Int {
        let nsText = text as NSString
        var index = min(max(offset, 0), nsText.length)
        while index > 0 {
            guard let scalar = UnicodeScalar(nsText.character(at: index - 1)),
                  CharacterSet.alphanumerics.contains(scalar)
                    || scalar == "_" || scalar == "\\" || scalar == "$" else {
                break
            }
            index -= 1
        }
        return index
    }

    nonisolated static func query(in text: String, from start: Int, to end: Int) -> String {
        let nsText = text as NSString
        let location = min(max(start, 0), nsText.length)
        let length = min(max(end, location), nsText.length) - location
        return nsText.substring(with: NSRange(location: location, length: length))
    }
}
