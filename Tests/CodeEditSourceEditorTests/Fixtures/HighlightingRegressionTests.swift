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

        XCTAssertTrue(hasHTMLTag, "Expected the HTML div tag to be highlighted inside PHP")
    }

    @MainActor
    func test_markdownInlineRangesAreCoalesced() {
        let (client, _) = makeClient(
            text: HighlightingFixtures.multipleMarkdownInlineIslands,
            language: .markdown
        )

        let inlineLayers = client.state?.layers.filter { $0.id == .markdownInline } ?? []
        let rangeCount = inlineLayers.reduce(0) { $0 + $1.ranges.count }

        XCTAssertEqual(inlineLayers.count, 1, "Expected one coalesced markdown inline layer")
        XCTAssertGreaterThanOrEqual(rangeCount, 2, "Expected multiple inline ranges in the zone")
    }

    @MainActor
    func test_editInsidePHPHTMLKeepsCoalescedZones() {
        let text = HighlightingFixtures.mixedPHPHTML
        let (client, textView) = makeClient(text: text, language: .php)
        let divLocation = (text as NSString).range(of: "<div").location + 4
        let editExpectation = expectation(description: "HTML edit completes")

        performEdit(
            textView: textView,
            client: client,
            string: " class=\"edited\"",
            range: NSRange(location: divLocation, length: 0)
        ) { result in
            if case .success = result {
                editExpectation.fulfill()
            } else {
                XCTFail("HTML edit failed")
            }
        }
        wait(for: [editExpectation], timeout: 5.0)

        let htmlLayers = client.state?.layers.filter { $0.id == .html } ?? []
        XCTAssertEqual(htmlLayers.count, 1, "Editing HTML must keep a single coalesced HTML zone")

        let editedText = textView.string
        let highlights = client.queryHighlightsForRange(
            range: NSRange(location: 0, length: (editedText as NSString).length)
        )
        XCTAssertTrue(
            highlights.contains { $0.capture == .tag && editedText.substring(with: $0.range) == "div" },
            "Expected HTML tags to remain highlighted after an edit"
        )
    }

    @MainActor
    func test_insertingStyleCreatesNestedCSSZone() {
        let fixture = HighlightingFixtures.multiplePHPHTMLIslands
        let (client, textView) = makeClient(text: fixture, language: .php)
        let sectionEnd = NSMaxRange((fixture as NSString).range(of: "<section class=\"one\">"))
        let editExpectation = expectation(description: "Style insertion completes")

        performEdit(
            textView: textView,
            client: client,
            string: "\n<style>.added { color: blue; }</style>",
            range: NSRange(location: sectionEnd, length: 0)
        ) { result in
            if case .success = result {
                editExpectation.fulfill()
            } else {
                XCTFail("Style insertion failed")
            }
        }
        wait(for: [editExpectation], timeout: 5.0)

        let cssLayers = client.state?.layers.filter { $0.id == .css } ?? []
        XCTAssertEqual(cssLayers.count, 1, "Expected the new style element to create a CSS zone")

        let editedText = textView.string
        let highlights = client.queryHighlightsForRange(
            range: NSRange(location: 0, length: (editedText as NSString).length)
        )
        XCTAssertTrue(
            highlights.contains { $0.capture == .property && editedText.substring(with: $0.range) == "color" },
            "Expected the newly inserted CSS to be highlighted"
        )
    }

    @MainActor
    func test_removingStyleRemovesCSSZone() {
        let fixture = HighlightingFixtures.mixedPHPHTML
        let (client, textView) = makeClient(text: fixture, language: .php)
        let styleStart = (fixture as NSString).range(of: "<style>").location
        let styleEnd = NSMaxRange((fixture as NSString).range(of: "</style>"))
        XCTAssertNotEqual(styleStart, NSNotFound)
        let styleRange = NSRange(location: styleStart, length: styleEnd - styleStart)

        let editExpectation = expectation(description: "Style deletion completes")
        performEdit(
            textView: textView,
            client: client,
            string: "",
            range: styleRange
        ) { result in
            if case .success = result {
                editExpectation.fulfill()
            } else {
                XCTFail("Style deletion failed")
            }
        }
        wait(for: [editExpectation], timeout: 5.0)

        let cssLayers = client.state?.layers.filter { $0.id == .css } ?? []
        XCTAssertTrue(cssLayers.isEmpty, "Expected the removed style element to remove its CSS zone")
    }

    @MainActor
    func test_editingOneIslandParsesOnlyDirtyLayers() {
        let fixture = HighlightingFixtures.largeMixedPHP()
        let (client, textView) = makeClient(text: fixture, language: .php)
        let layerCount = client.state?.layers.count ?? 0
        HighlightingMetrics.shared.reset()

        let scriptLocation = (fixture as NSString).range(of: "const value0").location + 6
        let editExpectation = expectation(description: "JS island edit completes")

        performEdit(
            textView: textView,
            client: client,
            string: "x",
            range: NSRange(location: scriptLocation, length: 0)
        ) { result in
            if case .success = result {
                editExpectation.fulfill()
            } else {
                XCTFail("JS island edit failed")
            }
        }
        wait(for: [editExpectation], timeout: 10.0)

        let metrics = HighlightingMetrics.shared.current
        XCTAssertGreaterThan(metrics.dirtyLayers, 0)
        XCTAssertGreaterThan(metrics.parsedLayers, 0)
        XCTAssertLessThan(metrics.dirtyLayers, layerCount, "Editing one island must not mark every zone dirty")
        XCTAssertLessThan(metrics.parsedLayers, layerCount, "Editing one island must not parse every zone")
        XCTAssertLessThanOrEqual(
            metrics.injectionQueries,
            HighlightingFixtures.Thresholds.maxInjectionQueriesPerEdit
        )
    }

    @MainActor
    func test_scrollingVisibleChunksStayBounded() {
        let fixture = HighlightingFixtures.largeMixedPHP()
        let (client, _) = makeClient(text: fixture, language: .php)
        let length = (fixture as NSString).length

        for fraction in HighlightingFixtures.Thresholds.scrollOffsets {
            HighlightingMetrics.shared.reset()
            let location = min(max(0, Int(Double(length) * fraction)), max(0, length - 1))
            let visibleLength = min(
                HighlightingFixtures.Thresholds.visibleChunkLength,
                length - location
            )
            _ = client.queryHighlightsForRange(
                range: NSRange(location: location, length: visibleLength)
            )

            let metrics = HighlightingMetrics.shared.current
            XCTAssertEqual(metrics.highlightQueries, 1)
            XCTAssertGreaterThan(metrics.layersVisited, 0)
            XCTAssertLessThan(
                metrics.layersVisited,
                HighlightingFixtures.Thresholds.maxVisibleLayers,
                "Scroll chunk at \(fraction) must not scan every zone"
            )
            XCTAssertLessThan(
                metrics.highlightQueryIntersections,
                HighlightingFixtures.Thresholds.maxVisibleIntersections,
                "Scroll chunk at \(fraction) must stay proportional to visible zones"
            )
        }
    }

    @MainActor
    func test_languageChangeRemovesStaleZones() {
        let (client, textView) = makeClient(
            text: HighlightingFixtures.mixedPHPHTML,
            language: .php
        )
        XCTAssertTrue(client.state?.layers.contains { $0.id == .html } ?? false)

        let swiftText = "func value() -> Int { 42 }"
        textView.setText(swiftText)
        client.setUp(textView: textView, codeLanguage: .swift)

        let state = client.state
        XCTAssertEqual(state?.primaryLayer.id, .swift)
        XCTAssertTrue(
            state?.layers.allSatisfy { $0.id == .swift && $0.depth == 0 } ?? false,
            "Changing language must discard every zone from the previous language"
        )
    }

    @MainActor
    func test_phpHTMLCSSAndJavaScriptZonesHighlight() {
        let text = HighlightingFixtures.mixedPHPHTML
        let (client, _) = makeClient(text: text, language: .php)
        let documentRange = NSRange(location: 0, length: (text as NSString).length)
        let highlights = client.queryHighlightsForRange(range: documentRange)

        let htmlLayers = client.state?.layers.filter { $0.id == .html } ?? []
        let cssLayers = client.state?.layers.filter { $0.id == .css } ?? []
        let jsLayers = client.state?.layers.filter { $0.id == .javascript } ?? []

        XCTAssertEqual(htmlLayers.count, 1, "Expected one coalesced HTML zone")
        XCTAssertEqual(cssLayers.count, 1, "Expected one CSS zone")
        XCTAssertEqual(jsLayers.count, 1, "Expected one JavaScript zone")
        XCTAssertGreaterThanOrEqual(htmlLayers.first?.ranges.count ?? 0, 2)

        XCTAssertTrue(
            highlights.contains { $0.capture == .property && text.substring(with: $0.range) == "color" },
            "Expected the CSS color property to be highlighted"
        )
        XCTAssertTrue(
            highlights.contains { $0.capture == .keyword && text.substring(with: $0.range) == "const" },
            "Expected the JavaScript const keyword to be highlighted"
        )
    }

    @MainActor
    func test_multiplePHPIslandsShareOneHTMLZone() {
        let (client, _) = makeClient(
            text: HighlightingFixtures.multiplePHPHTMLIslands,
            language: .php
        )

        let htmlLayers = client.state?.layers.filter { $0.id == .html } ?? []
        let rangeCount = htmlLayers.reduce(0) { $0 + $1.ranges.count }

        XCTAssertEqual(htmlLayers.count, 1, "Expected one HTML zone for every PHP text island")
        XCTAssertGreaterThanOrEqual(rangeCount, 2, "Expected multiple coalesced HTML ranges")
    }

    @MainActor
    func test_nestedHTMLZonesCreateCSSAndJavaScriptZones() {
        let text = HighlightingFixtures.nestedZones
        let (client, _) = makeClient(text: text, language: .html)

        let cssLayers = client.state?.layers.filter { $0.id == .css } ?? []
        let jsLayers = client.state?.layers.filter { $0.id == .javascript } ?? []

        XCTAssertEqual(cssLayers.count, 1, "Expected the HTML style element to create one CSS zone")
        XCTAssertEqual(jsLayers.count, 1, "Expected the HTML script element to create one JavaScript zone")
        XCTAssertEqual(cssLayers.first?.depth, 1)
        XCTAssertEqual(jsLayers.first?.depth, 1)

        let importLocation = (text as NSString).range(of: "import").location
        XCTAssertEqual(
            client.state?.zoneIndex.deepestSpan(at: importLocation)?.layer.id,
            .javascript,
            "Expected the zone index to select the nested JavaScript zone"
        )
    }

    @MainActor
    func test_largeMixedPHPVisibleChunkVisitsFewZones() {
        HighlightingMetrics.shared.reset()

        let fixture = HighlightingFixtures.largeMixedPHP()
        let (client, _) = makeClient(text: fixture, language: .php)
        _ = client.queryHighlightsForRange(
            range: NSRange(
                location: 0,
                length: min(HighlightingFixtures.Thresholds.visibleChunkLength, (fixture as NSString).length)
            )
        )

        let metrics = HighlightingMetrics.shared.current
        XCTAssertGreaterThan(metrics.layersVisited, 0)
        XCTAssertLessThan(
            metrics.layersVisited,
            HighlightingFixtures.Thresholds.maxVisibleLayers,
            "A visible chunk must not scan every zone"
        )
    }

    @MainActor
    func test_largeMixedPHPUsesOneZonePerLanguage() {
        let fixture = HighlightingFixtures.largeMixedPHP()
        let (client, _) = makeClient(text: fixture, language: .php)

        let htmlLayers = client.state?.layers.filter { $0.id == .html } ?? []
        let cssLayers = client.state?.layers.filter { $0.id == .css } ?? []
        let jsLayers = client.state?.layers.filter { $0.id == .javascript } ?? []

        XCTAssertEqual(htmlLayers.count, 1, "Every PHP text island should share one HTML zone")
        XCTAssertEqual(cssLayers.count, 1, "Every style element should share one CSS zone")
        XCTAssertEqual(jsLayers.count, 1, "Every script element should share one JavaScript zone")
        XCTAssertGreaterThan(htmlLayers.first?.ranges.count ?? 0, 100)
        XCTAssertGreaterThan(cssLayers.first?.ranges.count ?? 0, 100)
        XCTAssertGreaterThan(jsLayers.first?.ranges.count ?? 0, 100)
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
        XCTAssertGreaterThan(metrics.dirtyLayers, 0)
        XCTAssertGreaterThan(metrics.parsedLayers, 0)
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

        let queryRange = NSRange(
            location: 0,
            length: min(HighlightingFixtures.Thresholds.visibleChunkLength, (text as NSString).length)
        )
        let queryStart = clock.now
        _ = client.queryHighlightsForRange(range: queryRange)
        let queryDuration = queryStart.duration(to: clock.now)

        let scrollStart = clock.now
        for fraction in HighlightingFixtures.Thresholds.scrollOffsets {
            let location = min(
                Int(Double((text as NSString).length) * fraction),
                (text as NSString).length - 1
            )
            _ = client.queryHighlightsForRange(
                range: NSRange(
                    location: location,
                    length: min(
                        HighlightingFixtures.Thresholds.visibleChunkLength,
                        (text as NSString).length - location
                    )
                )
            )
        }
        let scrollDuration = scrollStart.duration(to: clock.now)

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

        let languageStart = clock.now
        textView.setText("func value() -> Int { 42 }")
        client.setUp(textView: textView, codeLanguage: .swift)
        let languageDuration = languageStart.duration(to: clock.now)

        print(
            "HP5 baseline largeMixedPHP bytes=\(text.utf8.count) "
                + "open=\(openDuration) query=\(queryDuration) scroll=\(scrollDuration) "
                + "edit=\(editDuration) languageChange=\(languageDuration)"
        )
    }

    func test_largeMixedPHPFixtureShape() {
        let fixture = HighlightingFixtures.largeMixedPHP()
        let islandCount = fixture.components(separatedBy: "<section").count - 1

        XCTAssertEqual(islandCount, 300)
        XCTAssertGreaterThan(fixture.utf8.count, 900_000)
    }
}

private extension String {
    func substring(with range: NSRange) -> String {
        (self as NSString).substring(with: range)
    }
}
