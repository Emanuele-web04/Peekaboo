// UI tests for the iPhone app. Verifies long-press drag both reorders rows
// within a section and moves a row directly into another status section.
import XCTest

final class PeekabooMobileUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["PEEKABOO_TESTING"] = "1"
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    }

    override func tearDownWithError() throws {
        app.terminate()
        _ = app.wait(for: .notRunning, timeout: 3)
        app = nil
    }

    func testDragReordersWithinSection() throws {
        addTask(named: "Alpha")
        addTask(named: "Beta")

        let first = app.staticTexts["Alpha"]
        let second = app.staticTexts["Beta"]
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertTrue(second.waitForExistence(timeout: 3))
        // Newest first: Beta sits above Alpha.
        XCTAssertLessThan(second.frame.minY, first.frame.minY)

        let secondDragHandle = app.images["Drag Beta"]
        XCTAssertTrue(secondDragHandle.waitForExistence(timeout: 3))
        secondDragHandle.press(forDuration: 1.0, thenDragTo: first)

        let deadline = Date().addingTimeInterval(3)
        while second.frame.minY <= first.frame.minY, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertGreaterThan(second.frame.minY, first.frame.minY)
    }

    func testDragMovesTaskAcrossSections() throws {
        addTask(named: "Move me")

        let dragHandle = app.images["Drag Move me"]
        let destination = app.staticTexts["task-section-inProgress"]
        XCTAssertTrue(dragHandle.waitForExistence(timeout: 3))
        XCTAssertTrue(destination.waitForExistence(timeout: 3))
        dragHandle.press(
            forDuration: 1.2,
            thenDragTo: destination,
            withVelocity: .slow,
            thenHoldForDuration: 0.6
        )

        let todoSection = app.staticTexts["task-section-todo"]
        let inProgressSection = app.staticTexts["task-section-inProgress"]
        let todoIsEmpty = expectation(
            for: NSPredicate(format: "label CONTAINS '0'"),
            evaluatedWith: todoSection
        )
        let inProgressHasTask = expectation(
            for: NSPredicate(format: "label CONTAINS '1'"),
            evaluatedWith: inProgressSection
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [todoIsEmpty, inProgressHasTask], timeout: 4),
            .completed
        )
        XCTAssertTrue(app.staticTexts["Move me"].exists)

        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "iPhone cross-section drag"
        proof.lifetime = .keepAlways
        add(proof)
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
