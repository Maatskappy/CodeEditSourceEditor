//
//  TreeSitterClient+Highlight.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 3/10/23.
//

import Foundation
import SwiftTreeSitter
import InbyLanguages

extension TreeSitterClient {
    func queryHighlightsForRange(range: NSRange) -> [HighlightRange] {
        guard let state = self.state else { return [] }

        var highlights: [HighlightRange] = []
        var injectedSet = IndexSet(integersIn: range)

        for layer in state.layers where layer.id != state.primaryLayer.id {
            // Query injected only if a layer's ranges intersects with `range`
            for layerRange in layer.ranges {
                if let rangeIntersection = range.intersection(layerRange) {
                    let queryResult = queryLayerHighlights(
                        layer: layer,
                        range: rangeIntersection
                    )

                    highlights.append(contentsOf: queryResult)
                    injectedSet.remove(integersIn: rangeIntersection)
                }
            }
        }

        // Query primary for any ranges that weren't used in the injected layers.
        for range in injectedSet.rangeView {
            let queryResult = queryLayerHighlights(
                layer: state.layers[0],
                range: NSRange(range)
            )
            highlights.append(contentsOf: queryResult)
        }

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

        // Two captures on the same range resolve to the one with the lowest capture index (its name appears first
        // in the query). Resolve that fully here, so exactly one highlight per range reaches the style container
        // whatever order tree-sitter yields the captures in.
        var winners: [NSRange: (index: Int, capture: CaptureName)] = [:]
        var order: [NSRange] = []
        for capture in cursor
            .resolve(with: .init(textProvider: readCallback)) // Resolve our cursor against the query
            .flatMap({ $0.captures }) {
            guard let captureName = CaptureName.fromString(capture.name) else { continue }
            let range = capture.range
            if let existing = winners[range] {
                if capture.index < existing.index {
                    winners[range] = (capture.index, captureName)
                }
            } else {
                winners[range] = (capture.index, captureName)
                order.append(range)
            }
        }

        return order.compactMap { range in
            guard let winner = winners[range] else { return nil }
            // Validate range
            let intersectionRange = range.intersection(includedRange) ?? .zero
            guard intersectionRange.length > 0 else {
                return nil
            }
            return HighlightRange(range: intersectionRange, capture: winner.capture)
        }
    }
}
