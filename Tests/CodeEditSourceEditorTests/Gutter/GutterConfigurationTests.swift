import XCTest
import AppKit
@testable import CodeEditSourceEditor

@MainActor
final class GutterConfigurationTests: XCTestCase {
    var controller: TextViewController!

    override func setUp() async throws {
        controller = Mock.textViewController(theme: Mock.theme())
        controller.loadView()
        controller.view.frame = NSRect(x: 0, y: 0, width: 1000, height: 1000)
        controller.view.layoutSubtreeIfNeeded()
    }

    func test_defaultsMatchPreviousBehaviour() {
        let appearance = controller.configuration.appearance
        XCTAssertNil(appearance.gutterFont)
        XCTAssertNil(appearance.gutterTextColor)
        XCTAssertNil(appearance.gutterSelectedLineTextColor)
        XCTAssertTrue(appearance.gutterHighlightsSelectedLineBackground)
        XCTAssertNil(appearance.gutterMinimumDigits)

        XCTAssertEqual(controller.gutterView.font, appearance.font.rulerFont)
        XCTAssertEqual(controller.gutterView.textColor, appearance.theme.text.color.withAlphaComponent(0.35))
        XCTAssertEqual(controller.gutterView.selectedLineTextColor, appearance.theme.text.color)
        XCTAssertTrue(controller.gutterView.highlightSelectedLines)
        XCTAssertEqual(controller.gutterView.minimumDigits, 3)
    }

    func test_gutterPicksUpFontAndColoursFromConfiguration() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        controller.configuration.appearance.gutterFont = font
        controller.configuration.appearance.gutterTextColor = .systemPurple
        controller.configuration.appearance.gutterSelectedLineTextColor = .systemOrange

        XCTAssertEqual(controller.gutterFont, font)
        XCTAssertEqual(controller.gutterView.font, font)
        XCTAssertEqual(controller.gutterView.textColor, .systemPurple)
        XCTAssertEqual(controller.gutterView.selectedLineTextColor, .systemOrange)

        // Clearing returns to the derived defaults.
        controller.configuration.appearance.gutterFont = nil
        controller.configuration.appearance.gutterTextColor = nil
        XCTAssertEqual(controller.gutterView.font, controller.font.rulerFont)
        XCTAssertEqual(
            controller.gutterView.textColor,
            controller.theme.text.color.withAlphaComponent(0.35)
        )
    }

    func test_gutterConfigurationSurvivesThemeAndFontChanges() {
        controller.configuration.appearance.gutterTextColor = .systemPurple
        controller.configuration.appearance.gutterFont = .systemFont(ofSize: 9)

        var theme = Mock.theme()
        theme.text = .init(color: .systemBrown)
        controller.configuration.appearance.theme = theme
        controller.configuration.appearance.font = .monospacedSystemFont(ofSize: 15, weight: .regular)

        XCTAssertEqual(controller.gutterView.textColor, .systemPurple)
        XCTAssertEqual(controller.gutterView.font, .systemFont(ofSize: 9))
    }

    func test_selectedLineBackgroundCanBeTurnedOff() {
        controller.configuration.appearance.gutterHighlightsSelectedLineBackground = false
        XCTAssertFalse(controller.gutterView.highlightSelectedLines)
        // The selected line's number still gets the selected text colour.
        XCTAssertEqual(controller.gutterView.selectedLineTextColor, controller.theme.text.color)

        controller.configuration.appearance.gutterHighlightsSelectedLineBackground = true
        XCTAssertTrue(controller.gutterView.highlightSelectedLines)
    }

    func test_readOnlyEditorKeepsExplicitSelectedLineColourWithoutFill() {
        controller.configuration.behavior.isEditable = false
        XCTAssertFalse(controller.gutterView.highlightSelectedLines)
        XCTAssertNil(controller.gutterView.selectedLineTextColor)

        controller.configuration.appearance.gutterSelectedLineTextColor = .systemOrange
        XCTAssertFalse(controller.gutterView.highlightSelectedLines)
        XCTAssertEqual(controller.gutterView.selectedLineTextColor, .systemOrange)

        // A theme change no longer re-enables the read-only gutter's selection emphasis.
        var theme = Mock.theme()
        theme.text = .init(color: .systemBrown)
        controller.configuration.appearance.gutterSelectedLineTextColor = nil
        controller.configuration.appearance.theme = theme
        XCTAssertNil(controller.gutterView.selectedLineTextColor)
        XCTAssertEqual(controller.gutterView.selectedLineColor, .clear)
    }

    func test_minimumDigitsReservesWidth() {
        let threeDigitWidth = controller.gutterView.frame.width
        controller.configuration.appearance.gutterMinimumDigits = 5
        XCTAssertEqual(controller.gutterView.minimumDigits, 5)
        let fiveDigitWidth = controller.gutterView.frame.width
        XCTAssertGreaterThan(fiveDigitWidth, threeDigitWidth)

        // The reserved width holds as the document grows past 3 digits.
        controller.setText(String(repeating: "x\n", count: 1200))
        controller.gutterView.updateWidthIfNeeded()
        XCTAssertEqual(controller.gutterView.frame.width, fiveDigitWidth)

        controller.configuration.appearance.gutterMinimumDigits = nil
        controller.gutterView.updateWidthIfNeeded()
        XCTAssertLessThan(controller.gutterView.frame.width, fiveDigitWidth)
    }

    func test_lineNumbersShareTheTextBaselineAtAnyGutterFontSize() throws {
        controller.configuration.appearance.lineHeightMultiple = 1.6
        controller.setText("let a = 1\nlet b = 2\n")
        _ = controller.textView.layoutManager.layoutLines()
        let line = try XCTUnwrap(controller.textView.layoutManager.textLineForIndex(0))
        let fragment = try XCTUnwrap(line.data.lineFragments.first?.data)
        let textBaseline = fragment.height - fragment.descent + fragment.heightDifference / 2

        for size in [8.0, 11.0, 16.0] {
            controller.configuration.appearance.gutterFont = .monospacedDigitSystemFont(ofSize: size, weight: .regular)
            let ctLine = CTLineCreateWithAttributedString(
                NSAttributedString(string: "1", attributes: [.font: controller.gutterView.font])
            )
            var ascent: CGFloat = 0
            CTLineGetTypographicBounds(ctLine, &ascent, nil, nil)
            XCTAssertEqual(
                controller.gutterView.lineNumberBaselineOffset(fragment: fragment, ascent: ascent),
                textBaseline,
                accuracy: 0.001
            )
        }
    }
}
