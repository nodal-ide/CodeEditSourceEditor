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
    var layers: [LanguageLayer] = []
    var zoneIndex = ZoneIndex()

    static let maximumZoneDepth = 8

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
                restrictedRange: nil,
                layersByKey: &layersByKey,
                touchedLayers: &touchedLayers
            )

            idx += 1
        }

        rebuildZoneIndex()
        recordDebugStateMetrics()
    }

    func recordDebugStateMetrics() {
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
}
