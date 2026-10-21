import XCTest
import CodeEditLanguages
import CodeEditTextView
@testable import CodeEditSourceEditor

final class HighlightingRegressionTests: XCTestCase {
    @MainActor
    private func makeClient(
        text: String,
        language: CodeLanguage
    ) -> (TreeSitterClient, TextView) {
        let client = Mock.treeSitterClient(forceSync: true)
        let textView = Mock.textView()
        textView.frame = NSRect(x: 0, y: 0, width: 1000, height: 1000)
        textView.setText(text)
        client.setUp(textView: textView, codeLanguage: language)
        return (client, textView)
    }

    @MainActor
    private func performEdit(
        textView: TextView,
        client: TreeSitterClient,
        string: String,
        range: NSRange,
        completion: @escaping (Result<IndexSet, Error>) -> Void
    ) {
        let delta = string.isEmpty ? -range.length : range.length
        textView.replaceString(in: range, with: string)
        client.applyEdit(textView: textView, range: range, delta: delta, completion: completion)
    }

    @MainActor
    func test_phpHTMLIslandHighlights() {
        let text = HighlightingFixtures.mixedPHPHTML
        let (client, _) = makeClient(text: text, language: .php)
        let documentRange = NSRange(location: 0, length: (text as NSString).length)
        let highlights = client.queryHighlightsForRange(range: documentRange)
        let divLocation = (text as NSString).range(of: "<div").location + 1

        let hasHTMLTag = highlights.contains {
            $0.capture == .tag
                && $0.range.location <= divLocation
                && NSMaxRange($0.range) >= divLocation + 3
        }

        XCTExpectFailure("PHP injections-text is pending HP2 coalescing.", strict: true) {
            XCTAssertTrue(hasHTMLTag, "Expected the HTML div tag to be highlighted inside PHP")
        }
    }

    @MainActor
    func test_markdownInlineRangesAreNotCoalescedYet() {
        let (client, _) = makeClient(
            text: HighlightingFixtures.multipleMarkdownInlineIslands,
            language: .markdown
        )

        let inlineLayers = client.state?.layers.filter { $0.id == .markdownInline } ?? []
        let rangeCount = inlineLayers.reduce(0) { $0 + $1.ranges.count }

        XCTAssertFalse(inlineLayers.isEmpty, "Expected markdown inline injection layers")
        XCTAssertGreaterThan(rangeCount, 0, "Expected markdown inline injection ranges")

        XCTExpectFailure("Injected ranges are coalesced in HP2.", strict: true) {
            XCTAssertEqual(inlineLayers.count, 1, "Expected one coalesced markdown inline layer")
            XCTAssertGreaterThanOrEqual(rangeCount, 2)
        }
    }

    @MainActor
    func test_debugMetricsRecordHighlightingWork() {
        HighlightingMetrics.shared.reset()

        let (client, textView) = makeClient(
            text: HighlightingFixtures.multipleMarkdownInlineIslands,
            language: .markdown
        )
        let documentRange = NSRange(
            location: 0,
            length: (HighlightingFixtures.multipleMarkdownInlineIslands as NSString).length
        )

        _ = client.queryHighlightsForRange(range: documentRange)

        let editExpectation = expectation(description: "Edit completes")
        performEdit(textView: textView, client: client, string: " ", range: .zero) { result in
            if case .success = result {
                editExpectation.fulfill()
            } else {
                XCTFail("Edit failed")
            }
        }
        wait(for: [editExpectation], timeout: 5.0)

        let metrics = HighlightingMetrics.shared.current
        XCTAssertGreaterThan(metrics.highlightQueries, 0)
        XCTAssertGreaterThan(metrics.layersVisited, 0)
        XCTAssertGreaterThan(metrics.highlightQueryIntersections, 0)
        XCTAssertGreaterThan(metrics.injectionQueries, 0)
        XCTAssertGreaterThan(metrics.invalidatedRanges, 0)
        XCTAssertGreaterThanOrEqual(metrics.maxLayerCount, 2)
        XCTAssertGreaterThan(metrics.maxRangeCount, 0)
    }

    @MainActor
    func test_baselineLargeMixedPHP() {
        let text = HighlightingFixtures.largeMixedPHP()
        let clock = ContinuousClock()

        let openStart = clock.now
        let (client, textView) = makeClient(text: text, language: .php)
        let openDuration = openStart.duration(to: clock.now)

        let queryRange = NSRange(location: 0, length: min(4000, (text as NSString).length))
        let queryStart = clock.now
        _ = client.queryHighlightsForRange(range: queryRange)
        let queryDuration = queryStart.duration(to: clock.now)

        let editRange = NSRange(location: (text as NSString).length / 2, length: 0)
        let editExpectation = expectation(description: "Baseline edit completes")
        let editStart = clock.now
        performEdit(textView: textView, client: client, string: " ", range: editRange) { result in
            if case .success = result {
                editExpectation.fulfill()
            } else {
                XCTFail("Baseline edit failed")
            }
        }
        wait(for: [editExpectation], timeout: 10.0)
        let editDuration = editStart.duration(to: clock.now)

        print(
            "HP0 baseline largeMixedPHP bytes=\(text.utf8.count) "
                + "open=\(openDuration) query=\(queryDuration) edit=\(editDuration)"
        )
    }

    func test_largeMixedPHPFixtureShape() {
        let fixture = HighlightingFixtures.largeMixedPHP()
        let islandCount = fixture.components(separatedBy: "<section").count - 1

        XCTAssertEqual(islandCount, 300)
        XCTAssertGreaterThan(fixture.utf8.count, 900_000)
    }
}
