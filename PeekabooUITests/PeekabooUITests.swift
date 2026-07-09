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

        XCTAssertTrue(app.menuItems["Copy"].waitForExistence(timeout: 2))

        let editTitle = app.menuItems["Edit title…"]
        XCTAssertTrue(editTitle.waitForExistence(timeout: 2))
        editTitle.click()

        let editField = app.textFields.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "edit-task-title-")
        ).firstMatch
        XCTAssertTrue(editField.waitForExistence(timeout: 2))
    }

    func testLongTaskTitleWrapsInsteadOfTruncating() throws {
        app.buttons["add-task-button"].click()

        let longTitle = "A long task title that should wrap onto multiple lines instead of being cut off"
        let titleField = app.textFields["new-task-title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.typeText(longTitle)
        titleField.typeKey(.return, modifierFlags: [])

        let title = app.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH %@", "A long task title")
        ).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        XCTAssertGreaterThan(title.frame.height, 20)
    }

    func testDragReordersTasksWithMatchingPriority() throws {
        addTask(named: "Alpha")
        addTask(named: "Beta")

        let first = app.staticTexts["Alpha"]
        let second = app.staticTexts["Beta"]
        XCTAssertTrue(first.waitForExistence(timeout: 2))
        XCTAssertTrue(second.waitForExistence(timeout: 2))
        XCTAssertLessThan(second.frame.minY, first.frame.minY)

        second.press(forDuration: 0.6, thenDragTo: first)

        let deadline = Date().addingTimeInterval(2)
        while second.frame.minY <= first.frame.minY && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertGreaterThan(second.frame.minY, first.frame.minY)
    }

    private func addTask(named title: String) {
        let addButton = app.buttons["add-task-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 2))
        addButton.click()

        let titleField = app.textFields["new-task-title"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 2))
        titleField.typeText(title)
        titleField.typeKey(.return, modifierFlags: [])
    }
}
