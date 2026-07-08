import XCTest

final class PeekabooUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["PEEKABOO_UI_TESTING"] = "1"
        app.launch()
    }

    func testCreateAdvanceCompleteAndOpenContextMenu() throws {
        let addButton = app.buttons["add-task-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        addButton.click()

        let titleField = app.textFields["new-task-title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.typeText("Ship prototype")
        titleField.typeKey(.return, modifierFlags: [])

        let title = app.staticTexts["Ship prototype"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.doubleClick()
        let inProgressSection = app.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@", "in progress")
        ).firstMatch
        XCTAssertTrue(inProgressSection.waitForExistence(timeout: 2))

        let markDone = app.buttons.matching(NSPredicate(format: "label == %@", "Mark done")).firstMatch
        XCTAssertTrue(markDone.waitForExistence(timeout: 2))
        markDone.click()
        let doneSection = app.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@", "done")
        ).firstMatch
        XCTAssertTrue(doneSection.waitForExistence(timeout: 2))

        let actions = app.menuButtons["Edit task"]
        XCTAssertTrue(actions.waitForExistence(timeout: 2))
        actions.click()

        let editTitle = app.menuItems["Edit title…"]
        XCTAssertTrue(editTitle.waitForExistence(timeout: 2))
        editTitle.click()

        let editField = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "edit-task-title-")
        ).firstMatch
        XCTAssertTrue(editField.waitForExistence(timeout: 2))
    }
}
