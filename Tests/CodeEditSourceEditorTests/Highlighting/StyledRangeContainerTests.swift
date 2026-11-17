import XCTest
@testable import CodeEditSourceEditor

final class StyledRangeContainerTests: XCTestCase {
    typealias Run = RangeStoreRun<StyledRangeContainer.StyleElement>

    @MainActor
    func test_init() {
        let providers = [0, 1]
        let store = StyledRangeContainer(documentLength: 100, providers: providers)

        // Have to do string conversion due to missing Comparable conformance pre-macOS 14
        XCTAssertEqual(store._storage.keys.sorted(), providers)
        XCTAssert(
            store._storage.values.allSatisfy({ $0.store.length == 100 }),
            "One or more providers have incorrect length"
        )
    }

    @MainActor
    func test_setHighlights() {
        let providers = [0, 1]
        let store = StyledRangeContainer(documentLength: 100, providers: providers)

        store.applyHighlightResult(
            provider: providers[0],
            highlights: [HighlightRange(range: NSRange(location: 40, length: 10), capture: .comment)],
            rangeToHighlight: NSRange(location: 0, length: 100)
        )

        XCTAssertNotNil(store._storage[providers[0]])
        XCTAssertEqual(store._storage[providers[0]]!.store.count, 3)
        XCTAssertNil(store._storage[providers[0]]!.store.runs(in: 0..<100)[0].value?.capture)
        XCTAssertEqual(store._storage[providers[0]]!.store.runs(in: 0..<100)[1].value?.capture, .comment)
        XCTAssertNil(store._storage[providers[0]]!.store.runs(in: 0..<100)[2].value?.capture)

        XCTAssertEqual(
            store.runsIn(range: NSRange(location: 0, length: 100)),
            [
                Run(length: 40, value: nil),
                Run(length: 10, value: .init(capture: .comment, modifiers: [])),
                Run(length: 50, value: nil)
            ]
        )
    }

    @MainActor
    func test_overlappingRuns() {
        let providers = [0, 1]
        let store = StyledRangeContainer(documentLength: 100, providers: providers)

        store.applyHighlightResult(
            provider: providers[0],
            highlights: [HighlightRange(range: NSRange(location: 40, length: 10), capture: .comment)],
            rangeToHighlight: NSRange(location: 0, length: 100)
        )

        store.applyHighlightResult(
            provider: providers[1],
            highlights: [
                HighlightRange(range: NSRange(location: 45, length: 5), capture: nil, modifiers: [.declaration])
            ],
            rangeToHighlight: NSRange(location: 0, length: 100)
        )

        XCTAssertEqual(
            store.runsIn(range: NSRange(location: 0, length: 100)),
            [
                Run(length: 40, value: nil),
                Run(length: 5, value: .init(capture: .comment, modifiers: [])),
                Run(length: 5, value: .init(capture: .comment, modifiers: [.declaration])),
                Run(length: 50, value: nil)
            ]
        )
    }

    @MainActor
    func test_overlappingRunsWithMoreProviders() {
        let providers = [0, 1, 2]
        let store = StyledRangeContainer(documentLength: 200, providers: providers)

        store.applyHighlightResult(
            provider: providers[0],
            highlights: [
                HighlightRange(range: NSRange(location: 30, length: 20), capture: .comment),
                HighlightRange(range: NSRange(location: 80, length: 30), capture: .string)
            ],
            rangeToHighlight: NSRange(location: 0, length: 200)
        )

        store.applyHighlightResult(
            provider: providers[1],
            highlights: [
                HighlightRange(range: NSRange(location: 35, length: 10), capture: nil, modifiers: [.declaration]),
                HighlightRange(range: NSRange(location: 90, length: 15), capture: .comment, modifiers: [.static])
            ],
            rangeToHighlight: NSRange(location: 0, length: 200)
        )

        store.applyHighlightResult(
            provider: providers[2],
            highlights: [
                HighlightRange(range: NSRange(location: 40, length: 5), capture: .function, modifiers: [.abstract]),
                HighlightRange(range: NSRange(location: 100, length: 10), capture: .number, modifiers: [.modification])
            ],
            rangeToHighlight: NSRange(location: 0, length: 200)
        )

        let runs = store.runsIn(range: NSRange(location: 0, length: 200))

        XCTAssertEqual(runs.reduce(0, { $0 + $1.length}), 200)

        XCTAssertEqual(runs[0], Run(length: 30, value: nil))
        XCTAssertEqual(runs[1], Run(length: 5, value: .init(capture: .comment, modifiers: [])))
        XCTAssertEqual(runs[2], Run(length: 5, value: .init(capture: .comment, modifiers: [.declaration])))
        XCTAssertEqual(runs[3], Run(length: 5, value: .init(capture: .comment, modifiers: [.abstract, .declaration])))
        XCTAssertEqual(runs[4], Run(length: 5, value: .init(capture: .comment, modifiers: [])))
        XCTAssertEqual(runs[5], Run(length: 30, value: nil))
        XCTAssertEqual(runs[6], Run(length: 10, value: .init(capture: .string, modifiers: [])))
        XCTAssertEqual(runs[7], Run(length: 10, value: .init(capture: .string, modifiers: [.static])))
        XCTAssertEqual(runs[8], Run(length: 5, value: .init(capture: .string, modifiers: [.static, .modification])))
        XCTAssertEqual(runs[9], Run(length: 5, value: .init(capture: .string, modifiers: [.modification])))
        XCTAssertEqual(runs[10], Run(length: 90, value: nil))
    }

    // MARK: Nested captures

    @MainActor
    func test_nestedCaptureSplitsEnclosingRun() {
        let store = StyledRangeContainer(documentLength: 6, providers: [0])
        store.applyHighlightResult(
            provider: 0,
            highlights: [
                HighlightRange(range: NSRange(location: 0, length: 6), capture: .string),
                HighlightRange(range: NSRange(location: 1, length: 4), capture: .variable)
            ],
            rangeToHighlight: NSRange(location: 0, length: 6)
        )

        XCTAssertEqual(
            store._storage[0]!.store.runs(in: 0..<6),
            [
                Run(length: 1, value: .init(capture: .string, modifiers: [])),
                Run(length: 4, value: .init(capture: .variable, modifiers: [])),
                Run(length: 1, value: .init(capture: .string, modifiers: []))
            ]
        )
    }

    @MainActor
    func test_deeplyNestedCapturesInnermostWins() {
        // "$(git rev-parse HEAD)" style: string 0..<20 ⊃ command 2..<15 ⊃ function 2..<5, plus a later variable.
        let store = StyledRangeContainer(documentLength: 30, providers: [0])
        store.applyHighlightResult(
            provider: 0,
            highlights: [
                HighlightRange(range: NSRange(location: 0, length: 20), capture: .string),
                HighlightRange(range: NSRange(location: 2, length: 13), capture: .keyword),
                HighlightRange(range: NSRange(location: 2, length: 3), capture: .function),
                HighlightRange(range: NSRange(location: 16, length: 2), capture: .variable),
                HighlightRange(range: NSRange(location: 22, length: 4), capture: .number)
            ],
            rangeToHighlight: NSRange(location: 0, length: 30)
        )

        XCTAssertEqual(
            store._storage[0]!.store.runs(in: 0..<30).map { Run(length: $0.length, value: $0.value) },
            [
                Run(length: 2, value: .init(capture: .string, modifiers: [])),
                Run(length: 3, value: .init(capture: .function, modifiers: [])),
                Run(length: 10, value: .init(capture: .keyword, modifiers: [])),
                Run(length: 1, value: .init(capture: .string, modifiers: [])),
                Run(length: 2, value: .init(capture: .variable, modifiers: [])),
                Run(length: 2, value: .init(capture: .string, modifiers: [])),
                Run(length: 2, value: nil),
                Run(length: 4, value: .init(capture: .number, modifiers: [])),
                Run(length: 4, value: nil)
            ]
        )
    }

    @MainActor
    func test_sameRangeTieKeepsFirstAndPartialOverlapIsSkipped() {
        let store = StyledRangeContainer(documentLength: 10, providers: [0])
        store.applyHighlightResult(
            provider: 0,
            highlights: [
                HighlightRange(range: NSRange(location: 0, length: 4), capture: .keyword),
                HighlightRange(range: NSRange(location: 0, length: 4), capture: .variable),
                HighlightRange(range: NSRange(location: 2, length: 4), capture: .string)
            ],
            rangeToHighlight: NSRange(location: 0, length: 10)
        )

        XCTAssertEqual(
            store._storage[0]!.store.runs(in: 0..<10).map { Run(length: $0.length, value: $0.value) },
            [
                Run(length: 4, value: .init(capture: .keyword, modifiers: [])),
                Run(length: 6, value: nil)
            ]
        )
    }
}
