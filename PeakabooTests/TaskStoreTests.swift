import XCTest
@testable import Peakaboo

final class TaskStoreTests: XCTestCase {
    @MainActor
    func testCreateNormalizesTitleAndRejectsEmptyInput() throws {
        let store = try makeTestStore()

        XCTAssertNil(store.create(title: "   \n  "))
        let task = store.create(title: "  Write   release\nnotes  ")

        XCTAssertEqual(task?.title, "Write release notes")
        XCTAssertEqual(task?.status, .todo)
        XCTAssertEqual(task?.priority, .medium)
        XCTAssertEqual(store.tasks.count, 1)
    }

    @MainActor
    func testTaskTransitionsAndRestoreMaintainCompletionDate() throws {
        let clock = MutableNow(Date(timeIntervalSince1970: 1_000))
        let store = try makeTestStore(now: { clock.value })
        let task = try XCTUnwrap(store.create(title: "Build panel", priority: .high))

        clock.value = Date(timeIntervalSince1970: 1_100)
        store.advanceToInProgress(task)
        XCTAssertEqual(task.status, .inProgress)
        XCTAssertNil(task.completedAt)

        clock.value = Date(timeIntervalSince1970: 1_200)
        store.markDone(task)
        XCTAssertEqual(task.status, .done)
        XCTAssertEqual(task.completedAt, clock.value)

        clock.value = Date(timeIntervalSince1970: 1_300)
        store.setStatus(.todo, for: task)
        XCTAssertEqual(task.status, .todo)
        XCTAssertNil(task.completedAt)
    }

    @MainActor
    func testOrderingUsesPriorityThenMostRecentUpdate() throws {
        let clock = MutableNow(Date(timeIntervalSince1970: 1_000))
        let store = try makeTestStore(now: { clock.value })
        let low = try XCTUnwrap(store.create(title: "Low", priority: .low))
        clock.value = Date(timeIntervalSince1970: 1_100)
        let highOlder = try XCTUnwrap(store.create(title: "High older", priority: .high))
        clock.value = Date(timeIntervalSince1970: 1_200)
        let highNewer = try XCTUnwrap(store.create(title: "High newer", priority: .high))

        XCTAssertEqual(store.orderedTasks(for: .todo).map(\.id), [highNewer.id, highOlder.id, low.id])

        clock.value = Date(timeIntervalSince1970: 1_300)
        store.rename(highOlder, to: "High most recent")
        XCTAssertEqual(store.orderedTasks(for: .todo).map(\.id), [highOlder.id, highNewer.id, low.id])
    }

    @MainActor
    func testNonePrioritySortsAfterLow() throws {
        let store = try makeTestStore()
        let none = try XCTUnwrap(store.create(title: "None", priority: .none))
        let low = try XCTUnwrap(store.create(title: "Low", priority: .low))

        XCTAssertEqual(store.orderedTasks(for: .todo).map(\.id), [low.id, none.id])
    }

    @MainActor
    func testDeleteRemovesTask() throws {
        let store = try makeTestStore()
        let task = try XCTUnwrap(store.create(title: "Temporary"))
        store.delete(task)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    @MainActor
    func testToggleCompletionReturnsDoneTaskToTodo() throws {
        let store = try makeTestStore()
        let task = try XCTUnwrap(store.create(title: "Toggle me"))

        store.toggleCompletion(task)
        XCTAssertEqual(task.status, .done)
        XCTAssertNotNil(task.completedAt)

        store.toggleCompletion(task)
        XCTAssertEqual(task.status, .todo)
        XCTAssertNil(task.completedAt)
    }

    @MainActor
    func testToggleProgressMovesBetweenTodoAndInProgress() throws {
        let store = try makeTestStore()
        let task = try XCTUnwrap(store.create(title: "Toggle progress"))

        store.toggleProgress(task)
        XCTAssertEqual(task.status, .inProgress)

        store.toggleProgress(task)
        XCTAssertEqual(task.status, .todo)

        store.markDone(task)
        store.toggleProgress(task)
        XCTAssertEqual(task.status, .done)
    }
}
