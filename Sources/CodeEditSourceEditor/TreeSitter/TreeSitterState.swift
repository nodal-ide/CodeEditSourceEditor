//
//  TreeSitterState.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 5/21/23.
//

import Foundation
import SwiftTreeSitter
import CodeEditLanguages

/// TreeSitterState contains the tree of language layers that make up the tree-sitter document.
public final class TreeSitterState {
    private(set) var primaryLayer: CodeLanguage
    private(set) var layers: [LanguageLayer] = []
    private(set) var zoneIndex = ZoneIndex()

    private static let maximumZoneDepth = 8

    // MARK: - Init

    /// Initialize a state object with a language and text view.
    /// - Parameters:
    ///   - codeLanguage: The language to use.
    ///   - readCallback: Callback used to read text for a specific range.
    ///   - readBlock: Callback used to read blocks of text.
    init(
        codeLanguage: CodeLanguage,
        readCallback: @escaping SwiftTreeSitter.Predicate.TextProvider,
        readBlock: @escaping Parser.ReadBlock
    ) {
        self.primaryLayer = codeLanguage
        self.setLanguage(codeLanguage)
        self.parseDocument(readCallback: readCallback, readBlock: readBlock)
    }

    /// Private initializer used by `copy`
    private init(codeLanguage: CodeLanguage, layers: [LanguageLayer]) {
        self.primaryLayer = codeLanguage
        self.layers = layers
        rebuildZoneIndex()
    }

    /// Creates a copy of the current state.
    ///
    /// This should be a fairly cheap operation. Copying tree-sitter trees never actually copies the contents, just
    /// increments a global ref counter.
    ///
    /// - Returns: A new, disconnected copy of the tree sitter state.
    public func copy() -> TreeSitterState {
        TreeSitterState(codeLanguage: primaryLayer, layers: layers.map { $0.copy() })
    }

    /// Sets the language for the state. Removing all existing layers.
    /// - Parameter codeLanguage: The language to use.
    private func setLanguage(_ codeLanguage: CodeLanguage) {
        layers.removeAll()

        primaryLayer = codeLanguage
        layers = [
            LanguageLayer(
                id: codeLanguage.id,
                tsLanguage: codeLanguage.language,
                parser: Parser(),
                supportsInjections: codeLanguage.additionalHighlights?.contains("injections") ?? false,
                tree: nil,
                languageQuery: TreeSitterModel.shared.query(for: codeLanguage.id),
                ranges: []
            )
        ]

        guard let treeSitterLanguage = codeLanguage.language else {
            rebuildZoneIndex()
            return
        }
        try? layers[0].parser.setLanguage(treeSitterLanguage)
        rebuildZoneIndex()
    }

    /// Performs the initial document parse for the primary layer.
    /// - Parameters:
    ///   - readCallback: The callback to use to read content from the document.
    ///   - readBlock: The callback to use to read blocks of content from the document.
    private func parseDocument(
        readCallback: @escaping SwiftTreeSitter.Predicate.TextProvider,
        readBlock: @escaping Parser.ReadBlock
    ) {
        layers[0].parser.timeout = 0.0
        layers[0].tree = layers[0].parser.parse(tree: nil as Tree?, readBlock: readBlock)

        var layersByKey = existingLayersByKey()
        var touchedLayers = Set<LanguageLayer>()

        // Use a while loop because `updateInjectedLanguageLayer` can add to `layers` during the loop.
        var idx = 0
        while idx < layers.count {
            updateInjectedLanguageLayer(
                readCallback: readCallback,
                readBlock: readBlock,
                layer: layers[idx],
                layersByKey: &layersByKey,
                touchedLayers: &touchedLayers
            )

            idx += 1
        }

        rebuildZoneIndex()
        recordDebugStateMetrics()
    }

    private func recordDebugStateMetrics() {
        #if DEBUG
        let rangeCount = layers.reduce(0) { $0 + $1.ranges.count }
        HighlightingMetrics.shared.recordState(layerCount: layers.count, rangeCount: rangeCount)
        #endif
    }

    // MARK: - Layer Management

    /// Removes a layer at the given index.
    /// - Parameter idx: The index of the layer to remove.
    public func removeLanguageLayer(at idx: Int) {
        layers.remove(at: idx)
        rebuildZoneIndex()
    }

    /// Removes all language layers in the given set.
    /// - Parameter set: A set of all language layers to remove.
    public func removeLanguageLayers(in set: Set<LanguageLayer>) {
        layers.removeAll(where: { set.contains($0) })
        rebuildZoneIndex()
    }

    /// Attempts to create a language layer and load a highlights file.
    /// Adds the layer to the `layers` array if successful.
    /// - Parameters:
    ///   - layerId: A language ID to add as a layer.
    ///   - readBlock: Completion called for efficient string lookup.
    ///   - parent: The layer this layer was injected into.
    ///   - sourceKey: The query or contribution that produced this layer.
    ///   - ranges: The initial ranges owned by this layer.
    public func addLanguageLayer(
        layerId: TreeSitterLanguage,
        readBlock: @escaping Parser.ReadBlock,
        parent: LanguageLayer? = nil,
        sourceKey: String? = nil,
        ranges: [NSRange] = []
    ) -> LanguageLayer? {
        guard let language = CodeLanguage.languageForID(layerId),
              let parserLanguage = language.language
        else {
            return nil
        }

        let zoneKey = parent.map {
            ZoneKey(parent: $0.id, language: layerId, sourceKey: sourceKey ?? "injections")
        }
        let newLayer = LanguageLayer(
            id: layerId,
            tsLanguage: language.language,
            parser: Parser(),
            supportsInjections: language.additionalHighlights?.contains("injections") ?? false,
            tree: nil,
            languageQuery: TreeSitterModel.shared.query(for: layerId),
            ranges: ranges,
            zoneKey: zoneKey,
            depth: (parent?.depth ?? -1) + 1
        )

        do {
            try newLayer.parser.setLanguage(parserLanguage)
        } catch {
            return nil
        }

        newLayer.parser.includedRanges = ranges.map { $0.tsRange }
        if !ranges.isEmpty {
            newLayer.tree = newLayer.parser.parse(tree: nil as Tree?, readBlock: readBlock)
        }

        layers.append(newLayer)
        rebuildZoneIndex()
        return newLayer
    }

    // MARK: - Injection Layers

    /// Inserts any new language layers, and removes any that may have been deleted after an edit.
    /// - Parameters:
    ///   - readCallback: Callback used to read text for a specific range.
    ///   - readBlock: Callback used to read blocks of text.
    ///   - touchedLayers: A set of layers. Each time a layer is visited, it will be removed from this set.
    ///                    Use this to determine if any layers were not modified after this method was run.
    ///                    Those layers should be removed.
    /// - Returns: A set of indices of any new layers. This set indicates ranges that should be re-highlighted.
    public func updateInjectedLayers(
        readCallback: @escaping SwiftTreeSitter.Predicate.TextProvider,
        readBlock: @escaping Parser.ReadBlock,
        touchedLayers: Set<LanguageLayer>
    ) -> IndexSet {
        var layersByKey = existingLayersByKey()
        var touchedLayers = touchedLayers
        var rangeSet = IndexSet()

        // Loop through each layer and apply injections query, add any ranges not previously found
        // using while loop because `updateInjectedLanguageLayer` can add to `layers` during the loop
        var idx = 0
        while idx < layers.count {
            let layer = layers[idx]

            if layer.supportsInjections {
                rangeSet.formUnion(
                    updateInjectedLanguageLayer(
                        readCallback: readCallback,
                        readBlock: readBlock,
                        layer: layer,
                        layersByKey: &layersByKey,
                        touchedLayers: &touchedLayers
                    )
                )
            }

            idx += 1
        }

        // Delete any layers that weren't touched at some point during the edit.
        removeLanguageLayers(in: touchedLayers)
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
    ///   - layersByKey: Existing layers keyed by their stable zone identity.
    ///   - touchedLayers: The set of layers that existed before this update. Existing layers are removed from it.
    /// - Returns: An index set of any updated indexes.
    @discardableResult
    private func updateInjectedLanguageLayer(
        readCallback: @escaping SwiftTreeSitter.Predicate.TextProvider,
        readBlock: @escaping Parser.ReadBlock,
        layer: LanguageLayer,
        layersByKey: inout [ZoneKey: LanguageLayer],
        touchedLayers: inout Set<LanguageLayer>
    ) -> IndexSet {
        guard let tree = layer.tree,
              let rootNode = tree.rootNode,
              let cursor = layer.languageQuery?.execute(node: rootNode, in: tree) else {
            return IndexSet()
        }

        cursor.matchLimit = TreeSitterClient.Constants.matchLimit

        #if DEBUG
        HighlightingMetrics.shared.recordInjectionQuery()
        #endif

        let injectionGroups = self.injectedLanguagesFrom(cursor: cursor) { range, point in
            return readCallback(range, point)
        }

        var updatedRanges = IndexSet()

        for (group, ranges) in injectionGroups {
            guard let treeSitterLanguage = TreeSitterLanguage.fromInjectionName(group.languageName) else {
                continue
            }

            guard layer.depth < Self.maximumZoneDepth,
                  !createsCycle(from: layer, injecting: treeSitterLanguage)
            else {
                continue
            }

            let zoneKey = ZoneKey(
                parent: layer.id,
                language: treeSitterLanguage,
                sourceKey: group.sourceKey
            )
            let coalescedRanges = coalescedRanges(ranges)

            guard !coalescedRanges.isEmpty else {
                continue
            }

            if let existingLayer = layersByKey[zoneKey] {
                touchedLayers.remove(existingLayer)

                if existingLayer.ranges != coalescedRanges {
                    updatedRanges.formUnion(indexSet(ranges: existingLayer.ranges))
                    updatedRanges.formUnion(indexSet(ranges: coalescedRanges))

                    existingLayer.ranges = coalescedRanges
                    existingLayer.parser.includedRanges = coalescedRanges.map { $0.tsRange }
                    existingLayer.tree = existingLayer.parser.parse(tree: nil as Tree?, readBlock: readBlock)
                }
            } else if let addedLayer = addLanguageLayer(
                layerId: treeSitterLanguage,
                readBlock: readBlock,
                parent: layer,
                sourceKey: group.sourceKey,
                ranges: coalescedRanges
            ) {
                layersByKey[zoneKey] = addedLayer
                updatedRanges.formUnion(indexSet(ranges: coalescedRanges))
            }
        }

        return updatedRanges
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

    private func existingLayersByKey() -> [ZoneKey: LanguageLayer] {
        var result: [ZoneKey: LanguageLayer] = [:]
        for layer in layers {
            if let key = layer.zoneKey {
                result[key] = layer
            }
        }
        return result
    }

    private func rebuildZoneIndex() {
        zoneIndex.rebuild(layers: layers)
    }

    private func coalescedRanges(_ ranges: [NamedRange]) -> [NSRange] {
        var indexSet = IndexSet()
        for range in ranges {
            indexSet.insert(integersIn: range.range)
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

    private func createsCycle(from layer: LanguageLayer, injecting language: TreeSitterLanguage) -> Bool {
        if language == primaryLayer.id || language == layer.id {
            return true
        }

        var current: LanguageLayer? = layer
        var visited = Set<TreeSitterLanguage>()

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
