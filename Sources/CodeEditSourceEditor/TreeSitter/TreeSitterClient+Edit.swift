//
//  TreeSitterClient+Edit.swift
//  
//
//  Created by Khan Winter on 3/10/23.
//

import Foundation
import SwiftTreeSitter
import CodeEditLanguages

extension TreeSitterClient {
    /// Applies the given edit to the current state and calls the editState's completion handler.
    ///
    /// Concurrency note: This method checks for task cancellation between layer edits, after editing all layers, and
    /// before setting the client's state.
    ///
    /// - Parameter edit: The edit to apply to the internal tree sitter state.
    /// - Returns: The set of ranges invalidated by the edit operation.
    // swiftlint:disable:next function_body_length
    func applyEdit(edit: InputEdit, range: NSRange) -> IndexSet {
        guard let state = state?.copy(), let readBlock, let readCallback else { return IndexSet() }
        let pendingEdits = pendingEdits.value() // Grab pending edits.
        let edits = pendingEdits + [edit]
        let dirtyProbe = pendingEdits.isEmpty ? Self.editProbeRange(for: range) : nil
        let dirtyLayers = dirtyLayers(in: state, intersecting: dirtyProbe)

        var invalidatedRanges = IndexSet()
        var dirtyRangeCount = 0
        var parsedLayers = 0

        if let dirtyProbe {
            dirtyRangeCount = state.layers.reduce(0) { count, layer in
                count + layer.ranges.filter { $0.intersection(dirtyProbe) != nil }.count
            }
        }

        // Apply the edit to every layer's ranges so later zones keep correct positions. Only dirty layers need
        // a parse/query; unaffected trees just receive the structural edit and keep their existing nodes.
        for (idx, layer) in state.layers.enumerated().reversed() {
            if Task.isCancelled { return IndexSet() }

            let isPrimary = layer.id == state.primaryLayer.id
            let isDirty = isPrimary || dirtyLayers.contains(layer)
            let keepLayer = updateLayer(
                layer,
                edits: edits,
                isPrimary: isPrimary,
                isDirty: isDirty,
                readBlock: readBlock,
                invalidatedRanges: &invalidatedRanges,
                parsedLayers: &parsedLayers
            )

            if !keepLayer {
                state.removeLanguageLayer(at: idx)
            }
        }

        if Task.isCancelled { return IndexSet() }

        // Update the state object for any new injections that may have been caused by this edit.
        invalidatedRanges.formUnion(state.updateInjectedLayers(
            readCallback: readCallback,
            readBlock: readBlock,
            dirtyLayers: dirtyLayers,
            dirtyRange: dirtyProbe
        ))

        if Task.isCancelled { return IndexSet() }

        self.state = state // Apply the copied state
        self.pendingEdits.mutate { edits in // Clear the queue
            edits = []
        }

        #if DEBUG
        HighlightingMetrics.shared.recordInvalidatedRanges(invalidatedRanges.count)
        HighlightingMetrics.shared.recordEdit(
            dirtyLayers: dirtyLayers.count,
            dirtyRanges: dirtyRangeCount,
            parsedLayers: parsedLayers
        )
        #endif

        return invalidatedRanges
    }

    private func updateLayer(
        _ layer: LanguageLayer,
        edits: [InputEdit],
        isPrimary: Bool,
        isDirty: Bool,
        readBlock: @escaping Parser.ReadBlock,
        invalidatedRanges: inout IndexSet,
        parsedLayers: inout Int
    ) -> Bool {
        if !isPrimary {
            applyEditTo(layer: layer, edits: edits)

            if layer.ranges.isEmpty {
                return false
            }
        }

        layer.parser.includedRanges = layer.ranges.map { $0.tsRange }

        if isDirty {
            let ranges = layer.findChangedByteRanges(
                edits: edits,
                timeout: Constants.parserTimeout,
                readBlock: readBlock
            )
            invalidatedRanges.insert(ranges: ranges)
            parsedLayers += 1
        } else {
            for edit in edits {
                layer.tree?.edit(edit)
            }
        }

        return true
    }

    private func dirtyLayers(in state: TreeSitterState, intersecting range: NSRange?) -> Set<LanguageLayer> {
        guard let range else {
            return Set(state.layers)
        }

        var result = Set<LanguageLayer>()
        if let primaryLayer = state.layers.first {
            result.insert(primaryLayer)
        }
        for span in state.zoneIndex.spans(intersecting: range) {
            result.insert(span.layer)
        }
        return result
    }

    private static func editProbeRange(for range: NSRange) -> NSRange {
        guard range.length == 0 else {
            return range
        }

        if range.location == 0 {
            return NSRange(location: 0, length: 1)
        }
        return NSRange(location: range.location - 1, length: 2)
    }

    private func applyEditTo(layer: LanguageLayer, edits: [InputEdit]) {
        // Reversed for safe removal while looping
        for rangeIdx in (0..<layer.ranges.count).reversed() {
            for edit in edits {
                layer.ranges[rangeIdx].applyInputEdit(edit)
            }

            if layer.ranges[rangeIdx].length <= 0 {
                layer.ranges.remove(at: rangeIdx)
            }
        }
    }
}
