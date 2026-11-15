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
            let field = app.textViews["Title"]
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
    func testReturnSavesWrappedTaskTitleOnCreateAndEdit() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-in-memory"]
        app.launch()
        app.buttons["New Task"].tap()
        let field = app.textViews["Title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let originalHeight = field.frame.height
        let title = "Review the project schedule and prepare detailed notes for the next planning meeting"
        field.typeText(title)
        XCTAssertGreaterThan(field.frame.height, originalHeight)
        app.typeText("\n")
        XCTAssertTrue(app.navigationBars["New Task"].waitForNonExistence(timeout: 5))
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "All Tasks")).firstMatch.tap()
        app.staticTexts[title].tap()
        XCTAssertTrue(app.navigationBars["Edit Task"].waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Updated title")
        field.typeText("\n")
        XCTAssertTrue(app.navigationBars["Edit Task"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Updated title")).firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testUnsavedListRequiresConfirmationOnSwipeAndCancel() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-in-memory"]
        app.launch()
        app.buttons["New List"].tap()
        let name = app.textFields["List name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Weekend\n")
        let bar = app.navigationBars["New List"]
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertTrue(app.buttons["Keep Editing"].waitForExistence(timeout: 5))
        app.buttons["Keep Editing"].tap()
        XCTAssertEqual(name.value as? String, "Weekend")
        start.press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5))
        app.buttons["New List"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Weekend\n")
        bar.buttons["Cancel"].tap()
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(bar.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testUnsavedTaskAndSearchEdit() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-in-memory"]
        app.launch()
        app.buttons["New Task"].tap()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["New Task"].waitForNonExistence(timeout: 5))
        app.buttons["New Task"].tap()
        let title = app.textViews["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("Original task")
        app.buttons["Close"].tap()
        app.buttons["Keep Editing"].tap()
        XCTAssertEqual(title.value as? String, "Original task")
        app.buttons["Save"].tap()
        app.buttons["Search"].tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 5))
        app.buttons["Original task"].tap()
        XCTAssertTrue(app.navigationBars["Edit Task"].waitForExistence(timeout: 5))
        title.tap()
        title.typeText(" changed")
        app.navigationBars["Edit Task"].buttons["Back"].tap()
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Original task"].firstMatch.exists)
    }

    @MainActor
    func testUnsavedGroupRequiresConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-in-memory"]
        app.launch()
        app.buttons["New List"].tap()
        let name = app.textFields["List name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Projects\n")
        app.buttons["Create"].tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Projects")).firstMatch.tap()
        app.buttons["New Group"].tap()
        let groupName = app.textFields["Group name"]
        XCTAssertTrue(groupName.waitForExistence(timeout: 5))
        groupName.typeText("Planning")
        app.buttons["Cancel"].tap()
        app.buttons["Keep Editing"].tap()
        XCTAssertEqual(groupName.value as? String, "Planning")
        app.buttons["Cancel"].tap()
        app.buttons["Discard Changes"].tap()
        XCTAssertTrue(app.navigationBars["New Group"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Planning"].exists)
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
