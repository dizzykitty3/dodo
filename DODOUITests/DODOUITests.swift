import XCTest

final class DODOUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testSingleCustomListScopesCreationAndSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-in-memory"]
        app.launch()

        func addTask(_ title: String) {
            app.buttons["New Task"].tap()
            let field = app.descendants(matching: .any).matching(identifier: "Title").firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(title)
            app.buttons["Save"].tap()
        }

        addTask("Outside task")
        app.buttons["New List"].tap()
        let name = app.textFields["List name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        app.typeText("Today")
        XCTAssertFalse(app.buttons["Create"].isEnabled)
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5) + "Projects\n")
        app.buttons["Teal"].tap()
        app.buttons["Work"].tap()
        XCTAssertTrue(app.buttons["Work"].isSelected)
        app.buttons["Create"].tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Projects")).firstMatch.tap()
        addTask("Inside task")
        XCTAssertTrue(app.staticTexts["Inside task"].waitForExistence(timeout: 5))
        app.buttons["Search"].tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 5))
        for title in ["Projects", "Other Tasks", "Inside task", "Outside task"] {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", title)).firstMatch.exists, title)
        }
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
