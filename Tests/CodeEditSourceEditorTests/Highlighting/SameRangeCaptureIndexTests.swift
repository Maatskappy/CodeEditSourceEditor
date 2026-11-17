import XCTest
import AppKit
import CodeEditTextView
import InbyLanguages
@testable import CodeEditSourceEditor

/// When two captures cover the same range, the one with the lower capture index (its name appears earlier in the
/// query file) wins. InbyLanguages' queries rely on this: YAML mapping keys list `@property` before `@string`, and
/// Python docstrings list `@comment` before `@string`.
final class SameRangeCaptureIndexTests: XCTestCase {
    @MainActor
    func flattenedCaptures(_ text: String, language: CodeLanguage) throws -> [String] {
        let textView = TextView(string: text)
        let client = Mock.treeSitterClient(forceSync: true)
        client.setUp(textView: textView, codeLanguage: language)
        var result: [HighlightRange]?
        client.queryHighlightsFor(textView: textView, range: textView.documentRange) { result = try? $0.get() }
        let highlights = try XCTUnwrap(result)
        let ns = text as NSString
        let runs = StyledRangeContainer.flattenHighlights(highlights, in: NSRange(location: 0, length: ns.length))
        var spans: [String] = []
        var location = 0
        for run in runs {
            if let capture = run.value?.capture {
                spans.append("\(ns.substring(with: NSRange(location: location, length: run.length))):\(capture)")
            }
            location += run.length
        }
        return spans
    }

    @MainActor
    func test_yamlMappingKeyIsPropertyNotString() throws {
        let spans = try flattenedCaptures("name: Inby\n", language: .yaml)
        XCTAssertEqual(spans, ["name:property", "Inby:string"])
    }

    @MainActor
    func test_pythonModuleDocstringIsComment() throws {
        let spans = try flattenedCaptures("\"\"\"doc\"\"\"\nx = \"s\"\n", language: .python)
        XCTAssertTrue(spans.contains("\"\"\"doc\"\"\":comment"), "\(spans)")
        XCTAssertFalse(spans.contains("\"\"\"doc\"\"\":string"), "\(spans)")
        XCTAssertTrue(spans.contains("\"s\":string"), "\(spans)")
    }

    @MainActor
    func test_readOnlyControllerColoursYamlKeyAsProperty() throws {
        let theme = Mock.theme()
        var config = Mock.config()
        config.behavior.isEditable = false
        let controller = TextViewController(
            string: "name: Inby\n",
            language: .yaml,
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
        while Date() < deadline && color(at: 6) != theme.strings.color {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertEqual(color(at: 6), theme.strings.color, "value")
        XCTAssertEqual(color(at: 0), theme.variables.color, "key")
    }
}
