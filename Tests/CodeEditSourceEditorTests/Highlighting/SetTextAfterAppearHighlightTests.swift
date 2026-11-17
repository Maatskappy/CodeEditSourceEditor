import XCTest
import AppKit
import CodeEditTextView
import InbyLanguages
@testable import CodeEditSourceEditor

/// Mirrors how Inby's code pane loads a file: the editor is created read-only with empty text, put in a window,
/// and the file's contents arrive later through `setText` (on appear and again on reloads).
final class SetTextAfterAppearHighlightTests: XCTestCase {
    static let snippet = """
    print -P "%F{blue}hi%f"
    alias ll="ls -la"
    function mkcd() {
      mkdir -p -- "$1" && cd -- "$1"
    }

    """

    @MainActor
    func makeController() -> (TextViewController, NSWindow) {
        var theme = Mock.theme()
        theme.background = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)
        var config = SourceEditorConfiguration(
            appearance: .init(
                theme: theme,
                useThemeBackground: true,
                font: .monospacedSystemFont(ofSize: 12.5, weight: .regular),
                lineHeightMultiple: 1.35,
                wrapLines: true,
                bracketPairEmphasis: .bordered(color: .systemOrange),
                gutterFont: .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular),
                gutterTextColor: .systemGray,
                gutterSelectedLineTextColor: .labelColor,
                gutterHighlightsSelectedLineBackground: false,
                gutterMinimumDigits: 4
            )
        )
        config.behavior.isEditable = false
        config.peripherals.showMinimap = false
        config.peripherals.showFoldingRibbon = false
        config.peripherals.showReformattingGuide = false

        let controller = TextViewController(
            string: "",
            language: .bash,
            configuration: config,
            cursorPositions: [],
            highlightProviders: [TreeSitterClient()]
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        controller.view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        controller.view.layoutSubtreeIfNeeded()
        return (controller, window)
    }

    @MainActor
    func waitForColor(_ controller: TextViewController, at location: Int, _ expected: NSColor) -> NSColor? {
        func color() -> NSColor? {
            guard location < controller.textView.textStorage.length else { return nil }
            return controller.textView.textStorage.attribute(.foregroundColor, at: location, effectiveRange: nil)
                as? NSColor
        }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline && color() != expected {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return color()
    }

    @MainActor
    func test_smallBashTextSetAfterAppearIsHighlighted() {
        let (controller, window) = makeController()
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        controller.setText(Self.snippet)
        XCTAssertEqual(waitForColor(controller, at: 42, controller.theme.keywords.color),
                       controller.theme.keywords.color, "`function` keyword")
        XCTAssertEqual(waitForColor(controller, at: 9, controller.theme.strings.color),
                       controller.theme.strings.color, "string")
    }

    @MainActor
    func test_tinyBashTextSetAfterAppearIsHighlighted() {
        let (controller, window) = makeController()
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        controller.setText("echo \"a\"\n")
        XCTAssertEqual(waitForColor(controller, at: 5, controller.theme.strings.color),
                       controller.theme.strings.color, "string")
    }

    @MainActor
    func test_reloadingSmallBashTextKeepsHighlighting() {
        let (controller, window) = makeController()
        defer { window.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        controller.setText(Self.snippet)
        _ = waitForColor(controller, at: 42, controller.theme.keywords.color)
        controller.setText(Self.snippet)
        XCTAssertEqual(waitForColor(controller, at: 42, controller.theme.keywords.color),
                       controller.theme.keywords.color, "`function` keyword after reload")
    }
}
