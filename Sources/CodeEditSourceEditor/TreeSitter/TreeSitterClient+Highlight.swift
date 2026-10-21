//
//  TreeSitterClient+Highlight.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 3/10/23.
//

import Foundation
import SwiftTreeSitter
import CodeEditLanguages

extension TreeSitterClient {
    func queryHighlightsForRange(range: NSRange) -> [HighlightRange] {
        guard let state = self.state else { return [] }

        var highlights: [HighlightRange] = []
        var covered = IndexSet()
        var layersVisited = 0
        var intersections = 0

        // Deepest spans win. Query each uncovered part of the span so nested languages override their parents
        // without scanning every layer and every range in the document.
        for span in state.zoneIndex.spans(intersecting: range) {
            layersVisited += 1

            guard let intersection = range.intersection(span.range) else {
                continue
            }

            var uncovered = IndexSet(integersIn: intersection)
            uncovered.subtract(covered)
            guard !uncovered.isEmpty else {
                continue
            }

            for queryRange in uncovered.rangeView {
                intersections += 1
                highlights.append(contentsOf: queryLayerHighlights(
                    layer: span.layer,
                    range: NSRange(queryRange)
                ))
            }

            covered.formUnion(IndexSet(integersIn: intersection))
        }

        // Query primary for any ranges that weren't used in the injected layers.
        var primaryRanges = IndexSet(integersIn: range)
        primaryRanges.subtract(covered)

        for primaryRange in primaryRanges.rangeView {
            intersections += 1
            let queryResult = queryLayerHighlights(
                layer: state.layers[0],
                range: NSRange(primaryRange)
            )
            highlights.append(contentsOf: queryResult)
        }

        #if DEBUG
        HighlightingMetrics.shared.recordHighlightQuery(
            layersVisited: layersVisited,
            intersections: intersections
        )
        #endif

        return highlights
    }

    /// Queries the given language layer for any highlights.
    /// - Parameters:
    ///   - layer: The layer to query.
    ///   - range: The range to query for.
    /// - Returns: Any ranges to highlight.
    internal func queryLayerHighlights(
        layer: LanguageLayer,
        range: NSRange
    ) -> [HighlightRange] {
        guard let tree = layer.tree,
              let rootNode = tree.rootNode else {
            return []
        }

        // This needs to be on the main thread since we're going to use the `textProvider` in
        // the `highlightsFromCursor` method, which uses the textView's text storage.
        guard let queryCursor = layer.languageQuery?.execute(node: rootNode, in: tree) else {
            return []
        }
        queryCursor.setRange(range)
        queryCursor.matchLimit =  Constants.matchLimit

        var highlights: [HighlightRange] = []

        // See https://github.com/CodeEditApp/CodeEditSourceEditor/pull/228
        if layer.id == .jsdoc {
            highlights.append(HighlightRange(range: range, capture: .comment))
        }

        highlights += highlightsFromCursor(cursor: queryCursor, includedRange: range)

        return highlights
    }

    /// Resolves a query cursor to the highlight ranges it contains.
    /// **Must be called on the main thread**
    /// - Parameters:
    ///     - cursor: The cursor to resolve.
    ///     - includedRange: The range to include highlights from.
    /// - Returns: Any highlight ranges contained in the cursor.
    internal func highlightsFromCursor(
        cursor: QueryCursor,
        includedRange: NSRange
    ) -> [HighlightRange] {
        guard let readCallback else { return [] }
        var ranges: [NSRange: Int] = [:]
        return cursor
            .resolve(with: .init(textProvider: readCallback)) // Resolve our cursor against the query
            .flatMap { $0.captures }
            .reversed() // SwiftTreeSitter returns captures in the reverse order of what we need to filter with.
            .compactMap { capture in
                let range = capture.range
                let index = capture.index

                // Lower indexed captures are favored over higher, this is why we reverse it above
                if let existingLevel = ranges[range], existingLevel <= index {
                    return nil
                }

                guard let captureName = CaptureName.fromString(capture.name) else {
                    return nil
                }

                // Update the filter level to the current index since it's lower and a 'valid' capture
                ranges[range] = index

                // Validate range and capture name
                let intersectionRange = range.intersection(includedRange) ?? .zero
                guard intersectionRange.length > 0 else {
                    return nil
                }

                return HighlightRange(range: intersectionRange, capture: captureName)
            }
    }
}
