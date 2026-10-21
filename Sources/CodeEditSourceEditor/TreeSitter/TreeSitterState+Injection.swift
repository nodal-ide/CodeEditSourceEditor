import Foundation
import SwiftTreeSitter
import CodeEditLanguages

extension TreeSitterState {
    // MARK: - Injection Layers

    /// Inserts any new language layers, and removes any that may have been deleted after an edit.
    /// - Parameters:
    ///   - readCallback: Callback used to read text for a specific range.
    ///   - readBlock: Callback used to read blocks of text.
    ///   - dirtyLayers: Layers whose trees changed during the edit. Only these layers are queried for injections.
    ///   - dirtyRange: The edited range. Limits coalesced layer queries to the affected ranges when possible.
    /// - Returns: A set of indices whose highlighting may have changed.
    public func updateInjectedLayers(
        readCallback: @escaping SwiftTreeSitter.Predicate.TextProvider,
        readBlock: @escaping Parser.ReadBlock,
        dirtyLayers: Set<LanguageLayer>,
        dirtyRange: NSRange? = nil
    ) -> IndexSet {
        var layersByKey = existingLayersByKey()
        var rangeSet = IndexSet()
        var candidates = injectionCandidates(dirtyLayers: dirtyLayers, dirtyRange: dirtyRange)

        let originalLayerCount = layers.count

        // Loop through each dirty layer and apply its injections query. Newly added layers are processed too so
        // nested zones can be discovered in the same edit.
        var idx = 0
        while idx < layers.count {
            let layer = layers[idx]
            let isNewLayer = idx >= originalLayerCount

            if layer.supportsInjections && (dirtyLayers.contains(layer) || isNewLayer) {
                rangeSet.formUnion(
                    updateInjectedLanguageLayer(
                        readCallback: readCallback,
                        readBlock: readBlock,
                        layer: layer,
                        restrictedRange: isNewLayer ? nil : dirtyRange,
                        layersByKey: &layersByKey,
                        touchedLayers: &candidates
                    )
                )
            }

            idx += 1
        }

        if let dirtyRange {
            trimUnmatchedLayers(
                candidates,
                dirtyRange: dirtyRange,
                readBlock: readBlock,
                rangeSet: &rangeSet
            )
        } else {
            removeLanguageLayers(in: candidates)
        }

        rebuildZoneIndex()
        recordDebugStateMetrics()

        return rangeSet
    }

    /// Performs an injections query on the given language layer.
    /// Updates any existing layers with new ranges and adds new layers if needed.
    /// - Parameters:
    ///   - readCallback: Callback used to read text for a specific range.
    ///   - readBlock: Callback used to read blocks of text.
    ///   - layer: The language layer to perform the query on.
    ///   - restrictedRange: The edited range to query, or `nil` to query the whole layer.
    ///   - layersByKey: Existing layers keyed by their stable zone identity.
    ///   - touchedLayers: Candidate layers under dirty parents. Existing layers are removed from it when found.
    /// - Returns: An index set of any updated indexes.
    @discardableResult
    func updateInjectedLanguageLayer(
        readCallback: @escaping SwiftTreeSitter.Predicate.TextProvider,
        readBlock: @escaping Parser.ReadBlock,
        layer: LanguageLayer,
        restrictedRange: NSRange?,
        layersByKey: inout [ZoneKey: LanguageLayer],
        touchedLayers: inout Set<LanguageLayer>
    ) -> IndexSet {
        let injectionGroups = injectionGroups(
            for: layer,
            restrictedRange: restrictedRange,
            readCallback: readCallback
        )
        var updatedRanges = IndexSet()

        for (group, ranges) in injectionGroups {
            updatedRanges.formUnion(updateInjectedGroup(
                group,
                ranges: ranges,
                layer: layer,
                restrictedRange: restrictedRange,
                readBlock: readBlock,
                layersByKey: &layersByKey,
                touchedLayers: &touchedLayers
            ))
        }

        return updatedRanges
    }

    // swiftlint:disable:next function_body_length
    private func updateInjectedGroup(
        _ group: InjectionGroup,
        ranges: [NamedRange],
        layer: LanguageLayer,
        restrictedRange: NSRange?,
        readBlock: @escaping Parser.ReadBlock,
        layersByKey: inout [ZoneKey: LanguageLayer],
        touchedLayers: inout Set<LanguageLayer>
    ) -> IndexSet {
        guard let treeSitterLanguage = catalog.language(forIdentifier: group.languageName)?.id,
              layer.depth < Self.maximumZoneDepth,
              !createsCycle(from: layer, injecting: treeSitterLanguage)
        else {
            return IndexSet()
        }

        let zoneKey = ZoneKey(
            parent: layer.id,
            language: treeSitterLanguage,
            sourceKey: group.sourceKey
        )
        var coalescedRanges = self.coalescedRanges(ranges.map(\.range))
        guard !coalescedRanges.isEmpty else {
            return IndexSet()
        }

        guard let existingLayer = layersByKey[zoneKey] else {
            guard let addedLayer = addLanguageLayer(
                layerId: treeSitterLanguage,
                readBlock: readBlock,
                parent: layer,
                sourceKey: group.sourceKey,
                ranges: coalescedRanges
            ) else {
                return IndexSet()
            }

            layersByKey[zoneKey] = addedLayer
            return indexSet(ranges: coalescedRanges)
        }

        touchedLayers.remove(existingLayer)

        if let restrictedRange {
            let unaffectedRanges = existingLayer.ranges.filter {
                $0.intersection(restrictedRange) == nil
            }
            coalescedRanges = self.coalescedRanges(unaffectedRanges + coalescedRanges)
        }

        guard existingLayer.ranges != coalescedRanges else {
            return IndexSet()
        }

        var updatedRanges = indexSet(ranges: existingLayer.ranges)
        updatedRanges.formUnion(indexSet(ranges: coalescedRanges))

        existingLayer.ranges = coalescedRanges
        existingLayer.parser.includedRanges = coalescedRanges.map { $0.tsRange }
        existingLayer.tree = existingLayer.parser.parse(tree: nil as Tree?, readBlock: readBlock)
        return updatedRanges
    }

    private func injectionGroups(
        for layer: LanguageLayer,
        restrictedRange: NSRange?,
        readCallback: @escaping SwiftTreeSitter.Predicate.TextProvider
    ) -> [InjectionGroup: [NamedRange]] {
        guard let tree = layer.tree,
              let rootNode = tree.rootNode,
              let languageQuery = layer.languageQuery
        else {
            return [:]
        }

        let queryRanges = injectionQueryRanges(for: layer, restrictedRange: restrictedRange)
        guard !queryRanges.isEmpty else {
            return [:]
        }

        var injectionGroups: [InjectionGroup: [NamedRange]] = [:]

        for queryRange in queryRanges {
            let cursor = languageQuery.execute(node: rootNode, in: tree)
            cursor.matchLimit = TreeSitterClient.Constants.matchLimit
            if let queryRange {
                cursor.setRange(queryRange)
            }

            #if DEBUG
            HighlightingMetrics.shared.recordInjectionQuery()
            #endif

            let groups = injectedLanguagesFrom(cursor: cursor) { range, point in
                return readCallback(range, point)
            }

            for (group, ranges) in groups {
                injectionGroups[group, default: []].append(contentsOf: ranges)
            }
        }

        return injectionGroups
    }

    private func injectionCandidates(
        dirtyLayers: Set<LanguageLayer>,
        dirtyRange: NSRange?
    ) -> Set<LanguageLayer> {
        guard let dirtyRange else {
            return Set(layers.filter { $0.zoneKey != nil })
        }

        let dirtyParentLanguages = Set(dirtyLayers.map(\.id))
        var candidates = Set<LanguageLayer>()

        for layer in layers {
            guard let key = layer.zoneKey, dirtyParentLanguages.contains(key.parent) else {
                continue
            }
            if layer.ranges.contains(where: { $0.intersection(dirtyRange) != nil }) {
                candidates.insert(layer)
            }
        }

        return candidates
    }

    /// Returns the ranges that should be queried for injections.
    private func injectionQueryRanges(
        for layer: LanguageLayer,
        restrictedRange: NSRange?
    ) -> [NSRange?] {
        guard let restrictedRange else {
            return [nil]
        }

        let padding = TreeSitterClient.Constants.injectionQueryPadding

        guard !layer.ranges.isEmpty else {
            return [expand(range: restrictedRange, lowerBound: 0, upperBound: nil, padding: padding)]
        }

        return layer.ranges.compactMap { layerRange in
            guard let intersection = layerRange.intersection(restrictedRange) else {
                return nil
            }
            return expand(
                range: intersection,
                lowerBound: layerRange.location,
                upperBound: NSMaxRange(layerRange),
                padding: padding
            )
        }
    }

    private func expand(
        range: NSRange,
        lowerBound: Int,
        upperBound: Int?,
        padding: Int
    ) -> NSRange {
        let start = max(lowerBound, range.location - padding)
        var end = NSMaxRange(range) + padding
        if let upperBound {
            end = min(upperBound, end)
        }
        return NSRange(location: start, length: max(0, end - start))
    }

    private func trimUnmatchedLayers(
        _ candidateLayers: Set<LanguageLayer>,
        dirtyRange: NSRange,
        readBlock: @escaping Parser.ReadBlock,
        rangeSet: inout IndexSet
    ) {
        for layer in candidateLayers {
            let remainingRanges = layer.ranges.filter { $0.intersection(dirtyRange) == nil }
            let removedRanges = layer.ranges.filter { $0.intersection(dirtyRange) != nil }

            if remainingRanges.isEmpty {
                rangeSet.formUnion(indexSet(ranges: layer.ranges))
                self.layers.removeAll { $0 === layer }
            } else {
                rangeSet.formUnion(indexSet(ranges: removedRanges))
                layer.ranges = remainingRanges
                layer.parser.includedRanges = remainingRanges.map { $0.tsRange }
                layer.tree = layer.parser.parse(tree: nil as Tree?, readBlock: readBlock)
            }
        }
    }

    /// Returns all injected languages from a given cursor. The cursor must be new,
    /// having not been used for normal highlight matching.
    /// - Parameters:
    ///   - cursor: The cursor to use for finding injected languages.
    ///   - textProvider: A callback for efficiently fetching text.
    /// - Returns: A map of each language/source pair to all the ranges injected by it.
    private func injectedLanguagesFrom(
        cursor: QueryCursor,
        textProvider: @escaping SwiftTreeSitter.Predicate.TextProvider
    ) -> [InjectionGroup: [NamedRange]] {
        var languages: [InjectionGroup: [NamedRange]] = [:]

        for match in cursor {
            guard let injection = match.injection(with: textProvider) else {
                continue
            }

            let sourceKey = match.metadata["injection.combined"] != nil
                ? "injections:combined"
                : "injections:pattern:\(match.patternIndex)"
            let group = InjectionGroup(languageName: injection.name, sourceKey: sourceKey)
            languages[group, default: []].append(injection)
        }

        return languages
    }

    private struct InjectionGroup: Hashable {
        let languageName: String
        let sourceKey: String
    }

    // MARK: - Zone Management

    func existingLayersByKey() -> [ZoneKey: LanguageLayer] {
        var result: [ZoneKey: LanguageLayer] = [:]
        for layer in layers {
            if let key = layer.zoneKey {
                result[key] = layer
            }
        }
        return result
    }

    func rebuildZoneIndex() {
        zoneIndex.rebuild(layers: layers)
    }

    private func coalescedRanges(_ ranges: [NSRange]) -> [NSRange] {
        var indexSet = IndexSet()
        for range in ranges {
            indexSet.insert(integersIn: range)
        }
        return indexSet.rangeView.map { NSRange($0) }.filter { $0.length > 0 }
    }

    private func indexSet(ranges: [NSRange]) -> IndexSet {
        var result = IndexSet()
        for range in ranges {
            result.insert(integersIn: range)
        }
        return result
    }

    private func createsCycle(from layer: LanguageLayer, injecting language: LanguageID) -> Bool {
        if language == primaryLayer.id || language == layer.id {
            return true
        }

        var current: LanguageLayer? = layer
        var visited = Set<LanguageID>()

        while let currentLayer = current, let key = currentLayer.zoneKey {
            if !visited.insert(currentLayer.id).inserted || key.parent == language {
                return true
            }
            current = layers.first {
                $0.zoneKey != nil && $0.id == key.parent && $0.depth == currentLayer.depth - 1
            }
        }

        return false
    }
}
