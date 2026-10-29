import SwiftUI
import XCTest
@testable import CodeEditSourceEditor

final class CompletionMatcherTests: XCTestCase {
    private struct Entry: CodeSuggestionEntry {
        let label: String
        var detail: String?
        var filterText: String?
        var sortText: String?
        var preselect: Bool = false
        var kind: CompletionItemKind = .unknown

        var documentation: String? { nil }
        var pathComponents: [String]? { nil }
        var targetPosition: CursorPosition? { nil }
        var sourcePreview: String? { nil }
        var image: Image { Image(systemName: "square") }
        var imageColor: Color { .clear }
        var deprecated: Bool { false }
        var isSnippet: Bool { false }
    }

    private func labels(_ items: [any CodeSuggestionEntry]) -> [String] {
        items.map(\.label)
    }

    func testExactPrefixRanksShortestFirst() {
        let items = [
            Entry(label: "TextFormField"),
            Entry(label: "Text"),
            Entry(label: "TextField")
        ]
        XCTAssertEqual(labels(CompletionMatcher.ranked(items, query: "Text")), ["Text", "TextField", "TextFormField"])
    }

    func testWordBoundaryMatching() {
        let items = [Entry(label: "SubtitleText"), Entry(label: "TextTheme"), Entry(label: "Theme")]
        let ranked = CompletionMatcher.ranked(items, query: "tt")
        XCTAssertEqual(ranked.first?.label, "TextTheme")
    }

    func testSubsequenceAndSubstring() {
        let items = [Entry(label: "Container"), Entry(label: "Text")]
        XCTAssertEqual(CompletionMatcher.ranked(items, query: "cnt").first?.label, "Container")
        XCTAssertEqual(CompletionMatcher.ranked(items, query: "ntain").first?.label, "Container")
    }

    func testNoMatchReturnsEmpty() {
        let items = [Entry(label: "Container")]
        XCTAssertTrue(CompletionMatcher.ranked(items, query: "zzz").isEmpty)
    }

    func testCaseInsensitive() {
        let items = [Entry(label: "MediaQuery")]
        XCTAssertEqual(CompletionMatcher.ranked(items, query: "media").first?.label, "MediaQuery")
    }

    func testFilterTextIsUsedForMatching() {
        let items = [Entry(label: "arrow_back", filterText: "arrowback")]
        XCTAssertEqual(CompletionMatcher.ranked(items, query: "arrowb").first?.label, "arrow_back")
    }

    func testSortTextBreaksScoreTies() {
        let items = [Entry(label: "Zeta", sortText: "b"), Entry(label: "Zulu", sortText: "a")]
        let ranked = CompletionMatcher.ranked(items, query: "z")
        XCTAssertEqual(labels(ranked), ["Zulu", "Zeta"])
    }

    func testProviderOrderIsPreservedForEqualItems() {
        let items = [Entry(label: "Alpha", detail: "first"), Entry(label: "Alpha", detail: "second")]
        let ranked = CompletionMatcher.ranked(items, query: "a")
        XCTAssertEqual(ranked.map(\.detail), ["first", "second"])
    }

    func testPreselectLeadsEmptyQuery() {
        let items = [Entry(label: "First"), Entry(label: "Second", preselect: true)]
        XCTAssertEqual(labels(CompletionMatcher.ranked(items, query: "")), ["Second", "First"])
    }

    func testLimitIsRespected() {
        let items = (0..<50).map { Entry(label: "Item\($0)") }
        XCTAssertEqual(CompletionMatcher.ranked(items, query: "Item", limit: 10).count, 10)
    }

    func testPrefixIsPreferredOverSubsequence() {
        let items = [Entry(label: "CountTextField"), Entry(label: "TextField")]
        XCTAssertEqual(CompletionMatcher.ranked(items, query: "text").first?.label, "TextField")
    }

    func testPrefixStartSkipsNonIdentifierCharacters() {
        let text = "final value = widget.contain"
        XCTAssertEqual(CompletionSession.prefixStart(in: text, before: text.count), text.count - 7)
        XCTAssertEqual(CompletionSession.prefixStart(in: "a + b", before: 5), 4)
    }

    func testQueryExtraction() {
        XCTAssertEqual(CompletionSession.query(in: "abc def", from: 4, to: 7), "def")
        XCTAssertEqual(CompletionSession.query(in: "abc", from: 0, to: 99), "abc")
    }
}
