//
//  StyledRangeContainer.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 10/13/24.
//

import Foundation

@MainActor
protocol StyledRangeContainerDelegate: AnyObject {
    func styleContainerDidUpdate(in range: NSRange)
}

/// Stores styles for any number of style providers. Provides an API for providers to store their highlights, and for
/// the overlapping highlights to be queried for a final highlight pass.
///
/// See ``runsIn(range:)`` for more details on how conflicting highlights are handled.
@MainActor
class StyledRangeContainer {
    struct StyleElement: RangeStoreElement, CustomDebugStringConvertible {
        var capture: CaptureName?
        var modifiers: CaptureModifierSet

        var isEmpty: Bool {
            capture == nil && modifiers.isEmpty
        }

        func combineLowerPriority(_ other: StyleElement?) -> StyleElement {
            StyleElement(
                capture: self.capture ?? other?.capture,
                modifiers: modifiers.union(other?.modifiers ?? [])
            )
        }

        func combineHigherPriority(_ other: StyleElement?) -> StyleElement {
            StyleElement(
                capture: other?.capture ?? self.capture,
                modifiers: modifiers.union(other?.modifiers ?? [])
            )
        }

        var debugDescription: String {
            "\(capture?.stringValue ?? "(empty)"), \(modifiers)"
        }
    }

    enum RunState {
        case empty
        case value(RangeStoreRun<StyleElement>)
        case exhausted

        var isExhausted: Bool {
            if case .exhausted = self { return true }
            return false
        }

        var hasValue: Bool {
            if case .value = self { return true }
            return false
        }

        var length: Int {
            switch self {
            case .empty, .exhausted:
                return 0
            case .value(let run):
                return run.length
            }
        }
    }

    var _storage: [ProviderID: (store: RangeStore<StyleElement>, priority: Int)] = [:]
    weak var delegate: StyledRangeContainerDelegate?

    /// Initialize the container with a list of provider identifiers. Each provider is given an id, they should be
    /// passed on here so highlights can be associated with a provider for conflict resolution.
    /// - Parameters:
    ///   - documentLength: The length of the document.
    ///   - providers: An array of identifiers given to providers.
    init(documentLength: Int, providers: [ProviderID]) {
        for provider in providers {
            _storage[provider] = (store: RangeStore<StyleElement>(documentLength: documentLength), priority: provider)
        }
    }

    func addProvider(_ id: ProviderID, priority: Int, documentLength: Int) {
        assert(!_storage.keys.contains(id), "Provider already exists")
        _storage[id] = (store: RangeStore<StyleElement>(documentLength: documentLength), priority: priority)
    }

    func setPriority(providerId: ProviderID, priority: Int) {
        _storage[providerId]?.priority = priority
    }

    func removeProvider(_ id: ProviderID) {
        guard let provider = _storage[id]?.store else { return }
        applyHighlightResult(
            provider: id,
            highlights: [],
            rangeToHighlight: NSRange(location: 0, length: provider.length)
        )
        _storage.removeValue(forKey: id)
    }

    func storageUpdated(editedRange: NSRange, changeInLength delta: Int) {
        for key in _storage.keys {
            _storage[key]?.store.storageUpdated(editedRange: editedRange, changeInLength: delta)
        }
    }
}

extension StyledRangeContainer: HighlightProviderStateDelegate {
    func updateStorageLength(newLength: Int) {
        for key in _storage.keys {
            guard var value = _storage[key] else { continue }
            var store = value.store
            let length = store.length
            if length != newLength {
                let missingCharacters = newLength - length
                if missingCharacters < 0 {
                    store.storageUpdated(replacedCharactersIn: (length + missingCharacters)..<length, withCount: 0)
                } else {
                    store.storageUpdated(replacedCharactersIn: length..<length, withCount: missingCharacters)
                }
            }

            value.store = store
            _storage[key] = value
        }
    }

    /// Applies a highlight result from a highlight provider to the storage container.
    ///
    /// Nested highlights are supported: a highlight strictly contained in an earlier one wins for its own sub-range,
    /// splitting the enclosing run around it (innermost wins). It inherits the enclosing highlight's capture when it
    /// has none of its own, and the union of both modifier sets. Two highlights with the same range keep the first one
    /// (the lower capture index). Partial, non-nested overlaps are skipped.
    ///
    /// - Parameters:
    ///   - provider: The provider sending the highlights.
    ///   - highlights: The highlights provided. These cannot be outside the range to highlight, must be ordered by
    ///                 position, but do not need to be continuous. Ranges not included in these highlights will be
    ///                 saved as empty.
    ///   - rangeToHighlight: The range to apply the highlights to.
    func applyHighlightResult(provider: ProviderID, highlights: [HighlightRange], rangeToHighlight: NSRange) {
        assert(rangeToHighlight != .notFound, "NSNotFound is an invalid highlight range")
        guard var storage = _storage[provider]?.store else {
            assertionFailure("No storage found for the given provider: \(provider)")
            return
        }
        let runs = Self.flattenHighlights(highlights, in: rangeToHighlight)
        storage.set(runs: runs, for: rangeToHighlight.intRange)
        _storage[provider]?.store = storage
        delegate?.styleContainerDidUpdate(in: rangeToHighlight)
    }

    /// Flattens possibly-nested highlights into a contiguous list of runs covering `rangeToHighlight`.
    ///
    /// Runs in O(n log n) for the ordering pass and O(n) for the sweep: every highlight is pushed and popped from the
    /// enclosing stack at most once.
    static func flattenHighlights(
        _ highlights: [HighlightRange],
        in rangeToHighlight: NSRange
    ) -> [RangeStoreRun<StyleElement>] {
        typealias Run = RangeStoreRun<StyleElement>
        // Order by start, then longest first so an enclosing highlight precedes the ones it contains when they share
        // a start. The sort is stable, so equal ranges keep provider order and the first still wins a tie.
        let ordered = highlights.enumerated().sorted { lhs, rhs in
            if lhs.element.range.location != rhs.element.range.location {
                return lhs.element.range.location < rhs.element.range.location
            }
            if lhs.element.range.length != rhs.element.range.length {
                return lhs.element.range.length > rhs.element.range.length
            }
            return lhs.offset < rhs.offset
        }

        var runs: [Run] = []
        runs.reserveCapacity(highlights.count * 2 + 1)
        var cursor = rangeToHighlight.lowerBound
        // Enclosing highlights whose tail past `cursor` is still to be emitted, innermost last.
        var stack: [(range: NSRange, element: StyleElement)] = []

        func emit(_ value: StyleElement?, upTo end: Int) {
            guard end > cursor else { return }
            runs.append(Run(length: end - cursor, value: value))
            cursor = end
        }

        for (_, highlight) in ordered {
            let range = highlight.range
            guard range.length > 0 else { continue }

            // Close every enclosing highlight that ends at or before this one starts.
            while let top = stack.last, top.range.max <= range.location {
                emit(top.element, upTo: top.range.max)
                stack.removeLast()
            }

            var element = StyleElement(capture: highlight.capture, modifiers: highlight.modifiers)
            if let top = stack.last {
                // `top` contains this highlight's start. Only a strictly nested highlight is kept.
                guard range.max <= top.range.max, range != top.range else { continue }
                element = top.element.combineHigherPriority(element)
                emit(top.element, upTo: range.location)
            } else {
                guard range.location >= cursor else { continue }
                emit(nil, upTo: range.location)
            }
            stack.append((range, element))
        }

        while let top = stack.popLast() {
            emit(top.element, upTo: top.range.max)
        }
        emit(nil, upTo: rangeToHighlight.upperBound)
        return runs
    }
}
