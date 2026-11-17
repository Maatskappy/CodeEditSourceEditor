import XCTest
import AppKit
import CodeEditTextView
import InbyLanguages
@testable import CodeEditSourceEditor

/// Regression coverage for a zsh-flavoured snippet that rendered with no highlighting in a staged Inby build.
/// With `.bash` the package highlights it fully; these tests pin that down from captures through to text attributes.
final class BashNestedHighlightTests: XCTestCase {
    static let source = """
    print -P "%F{blue}hi%f"
    alias ll="ls -la"
    function mkcd() {
      mkdir -p -- "$1" && cd -- "$1"
    }

    """

    @MainActor
    func test_bashCapturesFlattenWithNestedExpansions() throws {
        let textView = TextView(string: Self.source)
        let client = Mock.treeSitterClient(forceSync: true)
        client.setUp(textView: textView, codeLanguage: .bash)
        var result: [HighlightRange]?
        client.queryHighlightsFor(textView: textView, range: textView.documentRange) { result = try? $0.get() }
        let highlights = try XCTUnwrap(result)
        XCTAssertEqual(highlights.count, 16)

        let length = (Self.source as NSString).length
        let runs = StyledRangeContainer.flattenHighlights(highlights, in: NSRange(location: 0, length: length))
        XCTAssertEqual(runs.reduce(0) { $0 + $1.length }, length, "Runs must cover the whole document")

        var spans: [String] = []
        var location = 0
        for run in runs {
            if let capture = run.value?.capture { spans.append("\(location)+\(run.length) \(capture)") }
            location += run.length
        }
        XCTAssertEqual(spans, [
            "0+5 function", "6+2 constant", "9+14 string",
            "24+5 function", "33+8 string",
            "42+8 keyword", "51+4 function",
            "62+5 function", "68+2 constant", "71+2 constant",
            "74+2 string", "76+1 property", "77+1 string",
            "82+2 function", "85+2 constant",
            "88+2 string", "90+1 property", "91+1 string"
        ])
    }

    @MainActor
    func test_readOnlyControllerColoursBashEndToEnd() throws {
        let theme = Mock.theme()
        var config = Mock.config()
        config.behavior.isEditable = false
        let controller = TextViewController(
            string: Self.source,
            language: .bash,
            configuration: config,
            cursorPositions: [],
            highlightProviders: [Mock.treeSitterClient(forceSync: true)]
        )
        controller.loadView()
        controller.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 1000)
        controller.view.layoutSubtreeIfNeeded()
        controller.textView.layout()

        func color(at location: Int) -> NSColor? {
            controller.textView.textStorage.attribute(.foregroundColor, at: location, effectiveRange: nil) as? NSColor
        }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline && color(at: 42) != theme.keywords.color {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }

        XCTAssertEqual(color(at: 0), theme.commands.color, "print")
        XCTAssertEqual(color(at: 6), theme.values.color, "-P")
        XCTAssertEqual(color(at: 9), theme.strings.color, "\"%F{blue}hi%f\"")
        XCTAssertEqual(color(at: 42), theme.keywords.color, "function")
        XCTAssertEqual(color(at: 51), theme.commands.color, "mkcd")
        XCTAssertEqual(color(at: 71), theme.values.color, "--")
        XCTAssertEqual(color(at: 74), theme.strings.color, "opening quote of \"$1\"")
        XCTAssertEqual(color(at: 76), theme.variables.color, "1 inside \"$1\"")
        XCTAssertEqual(color(at: 77), theme.strings.color, "closing quote of \"$1\"")
    }
}
