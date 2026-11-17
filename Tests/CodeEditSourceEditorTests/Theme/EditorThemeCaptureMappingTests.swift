import XCTest
import AppKit
@testable import CodeEditSourceEditor

final class EditorThemeCaptureMappingTests: XCTestCase {
    let theme = Mock.theme()

    func test_functionAndMethodMapToCommands() {
        XCTAssertEqual(theme.colorFor(.function), theme.commands.color)
        XCTAssertEqual(theme.colorFor(.method), theme.commands.color)
    }

    func test_variablesPropertiesAndParametersStayOnVariables() {
        XCTAssertEqual(theme.colorFor(.variable), theme.variables.color)
        XCTAssertEqual(theme.colorFor(.property), theme.variables.color)
        XCTAssertEqual(theme.colorFor(.parameter), theme.variables.color)
    }

    func test_constantCapturesParseAndMapToValues() {
        XCTAssertEqual(CaptureName.fromString("constant"), .constant)
        XCTAssertEqual(CaptureName.fromString("constant.builtin"), .constantBuiltin)
        XCTAssertEqual(theme.colorFor(.constant), theme.values.color)
        XCTAssertEqual(theme.colorFor(.constantBuiltin), theme.values.color)
        XCTAssertEqual(theme.colorFor(CaptureName.fromString("constant")), theme.values.color)
    }
}
