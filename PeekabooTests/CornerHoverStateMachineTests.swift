import XCTest
@testable import Peekaboo

final class CornerHoverStateMachineTests: XCTestCase {
    func testRevealsOnlyAfterConfiguredDwell() {
        var machine = CornerHoverStateMachine()

        XCTAssertEqual(machine.update(at: 10, isInHotspot: true, isInPanel: false, isInteractionLocked: false, revealDelay: 0.5), .none)
        XCTAssertEqual(machine.update(at: 10.49, isInHotspot: true, isInPanel: false, isInteractionLocked: false, revealDelay: 0.5), .none)
        XCTAssertEqual(machine.update(at: 10.5, isInHotspot: true, isInPanel: false, isInteractionLocked: false, revealDelay: 0.5), .reveal)
        XCTAssertTrue(machine.isVisible)
    }

    func testLeavingHotspotBeforeDelayResetsDwell() {
        var machine = CornerHoverStateMachine()
        _ = machine.update(at: 1, isInHotspot: true, isInPanel: false, isInteractionLocked: false, revealDelay: 0.5)
        _ = machine.update(at: 1.4, isInHotspot: false, isInPanel: false, isInteractionLocked: false, revealDelay: 0.5)
        XCTAssertEqual(machine.update(at: 1.6, isInHotspot: true, isInPanel: false, isInteractionLocked: false, revealDelay: 0.5), .none)
    }

    func testPanelUsesTransitAndExitGracePeriods() {
        var machine = CornerHoverStateMachine()
        machine.forceVisible(at: 5, grace: 0.8)

        XCTAssertEqual(machine.update(at: 5.7, isInHotspot: false, isInPanel: false, isInteractionLocked: false, revealDelay: 0.5), .none)
        XCTAssertEqual(machine.update(at: 5.81, isInHotspot: false, isInPanel: false, isInteractionLocked: false, revealDelay: 0.5), .none)
        XCTAssertEqual(machine.update(at: 6.12, isInHotspot: false, isInPanel: false, isInteractionLocked: false, revealDelay: 0.5), .hide)
    }

    func testInteractionLockKeepsPanelVisible() {
        var machine = CornerHoverStateMachine()
        machine.forceVisible(at: 0, grace: 0)

        XCTAssertEqual(machine.update(at: 10, isInHotspot: false, isInPanel: false, isInteractionLocked: true, revealDelay: 0.5), .none)
        XCTAssertTrue(machine.isVisible)
    }

    func testConfiguredHideDelayControlsExitTiming() {
        var machine = CornerHoverStateMachine()
        machine.forceVisible(at: 0, grace: 0)

        XCTAssertEqual(machine.update(
            at: 1,
            isInHotspot: false,
            isInPanel: false,
            isInteractionLocked: false,
            revealDelay: 0.2,
            hideDelay: 0.7
        ), .none)
        XCTAssertEqual(machine.update(
            at: 1.69,
            isInHotspot: false,
            isInPanel: false,
            isInteractionLocked: false,
            revealDelay: 0.2,
            hideDelay: 0.7
        ), .none)
        XCTAssertEqual(machine.update(
            at: 1.7,
            isInHotspot: false,
            isInPanel: false,
            isInteractionLocked: false,
            revealDelay: 0.2,
            hideDelay: 0.7
        ), .hide)
    }
}

final class PanelUIStateTests: XCTestCase {
    @MainActor
    func testReleaseOutsideReturnsDraggedTaskOnce() {
        let state = PanelUIState()
        let task = TaskItem(title: "External drag")

        state.beginDragging(task)

        XCTAssertEqual(state.finishDragging(releasedOutsidePanel: true), task.id)
        XCTAssertNil(state.draggedTaskID)
        XCTAssertNil(state.finishDragging(releasedOutsidePanel: true))
    }

    @MainActor
    func testReleaseInsideClearsDragWithoutStartingTask() {
        let state = PanelUIState()
        let task = TaskItem(title: "Internal drag")

        state.beginDragging(task)

        XCTAssertNil(state.finishDragging(releasedOutsidePanel: false))
        XCTAssertNil(state.draggedTaskID)
    }
}
