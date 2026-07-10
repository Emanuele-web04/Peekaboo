// UI tests for the iPhone app. Mirrors the macOS drag-reorder coverage:
// verifies rows lift and reorder via long-press drag inside the list.
import XCTest

final class PeekabooMobileUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["PEEKABOO_TESTING"] = "1"
        app.launch()
    }

    func testDragReordersTasksWithMatchingPriority() throws {
        addTask(named: "Alpha")
        addTask(named: "Beta")

        let first = app.staticTexts["Alpha"]
        let second = app.staticTexts["Beta"]
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertTrue(second.waitForExistence(timeout: 3))
        // Newest first: Beta sits above Alpha.
        XCTAssertLessThan(second.frame.minY, first.frame.minY)

        second.press(forDuration: 1.0, thenDragTo: first)

        let deadline = Date().addingTimeInterval(3)
        while second.frame.minY <= first.frame.minY, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertGreaterThan(second.frame.minY, first.frame.minY)
    }

    func testDragAcrossDifferentPrioritiesSnapsBack() throws {
        addTask(named: "Urgent", priority: "High")
        addTask(named: "Casual", priority: "Medium")

        let high = app.staticTexts["Urgent"]
        let medium = app.staticTexts["Casual"]
        XCTAssertTrue(high.waitForExistence(timeout: 3))
        XCTAssertTrue(medium.waitForExistence(timeout: 3))
        // Priority sorting puts High above Medium.
        XCTAssertLessThan(high.frame.minY, medium.frame.minY)

        medium.press(forDuration: 1.0, thenDragTo: high)

        // The move is invalid, so the order must settle back unchanged.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertLessThan(high.frame.minY, medium.frame.minY)
    }

    func testDoubleTapMovesTaskToInProgress() throws {
        addTask(named: "Toggle me")

        let title = app.staticTexts["Toggle me"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.doubleTap()

        let inProgressSection = app.staticTexts["task-section-inProgress"]
        XCTAssertTrue(inProgressSection.waitForExistence(timeout: 3))
    }

    private func addTask(named title: String, priority: String? = nil) {
        let addButton = app.buttons["add-task-button"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        addButton.tap()

        let titleField = app.textViews["task-title-field"].exists
            ? app.textViews["task-title-field"]
            : app.textFields["task-title-field"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 3))
        titleField.typeText(title)

        if let priority {
            let chip = app.buttons["\(priority) priority"]
            XCTAssertTrue(chip.waitForExistence(timeout: 3))
            chip.tap()
        }

        let saveButton = app.buttons["save-task"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        saveButton.tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 3))
    }
}
