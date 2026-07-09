import XCTest
import UniformTypeIdentifiers
@testable import Peekaboo

final class TaskStoreTests: XCTestCase {
    func testTaskDragPayloadExportsInternalDataAndPlainText() {
        let payload = TaskDragPayload(title: "Paste me")
        let provider = payload.itemProvider()

        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.text.identifier))

        let plainTextLoaded = expectation(description: "Plain-text drag representation loads")
        provider.loadDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier) { data, error in
            XCTAssertNil(error)
            XCTAssertEqual(data, Data("Paste me".utf8))
            plainTextLoaded.fulfill()
        }
        wait(for: [plainTextLoaded], timeout: 1)

    }

    @MainActor
    func testCreateNormalizesTitleAndRejectsEmptyInput() throws {
        let store = try makeTestStore()

        XCTAssertNil(store.create(title: "   \n  "))
        let task = store.create(title: "  Write   release\nnotes  ")

        XCTAssertEqual(task?.title, "Write release notes")
        XCTAssertEqual(task?.status, .todo)
        XCTAssertEqual(task?.priority, TaskPriority.none)
        XCTAssertEqual(store.tasks.count, 1)
    }

    @MainActor
    func testCreateReportsPersistenceFailureAndRollsBack() throws {
        struct PersistenceFailure: Error {}
        let store = try makeTestStore(persist: { _ in throw PersistenceFailure() })

        XCTAssertNil(store.create(title: "Must not disappear"))
        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertNotNil(store.lastErrorMessage)
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
    func testPrimaryActionReturnsDoneTaskToTodo() throws {
        let store = try makeTestStore()
        let task = try XCTUnwrap(store.create(title: "Toggle me"))

        store.performPrimaryAction(task)
        XCTAssertEqual(task.status, .done)
        XCTAssertNotNil(task.completedAt)

        store.performPrimaryAction(task)
        XCTAssertEqual(task.status, .todo)
        XCTAssertNil(task.completedAt)
    }

    @MainActor
    func testDoubleClickActionMovesBetweenTodoAndInProgress() throws {
        let store = try makeTestStore()
        let task = try XCTUnwrap(store.create(title: "Toggle progress"))

        store.performDoubleClickAction(task)
        XCTAssertEqual(task.status, .inProgress)

        store.performDoubleClickAction(task)
        XCTAssertEqual(task.status, .todo)

        store.markDone(task)
        store.performDoubleClickAction(task)
        XCTAssertEqual(task.status, .done)
    }

    @MainActor
    func testBacklogReusesTaskRulesAndPromotesToTodo() throws {
        let store = try makeTestStore()
        let idea = try XCTUnwrap(store.create(
            title: "Explore CloudKit",
            priority: .high,
            status: .backlog
        ))

        XCTAssertEqual(idea.status, .backlog)
        XCTAssertEqual(idea.priority, .high)
        XCTAssertEqual(store.orderedTasks(for: .backlog).map(\.id), [idea.id])

        store.performPrimaryAction(idea)
        XCTAssertEqual(idea.status, .todo)
        XCTAssertNil(idea.completedAt)

        store.setStatus(.backlog, for: idea)
        store.performDoubleClickAction(idea)
        XCTAssertEqual(idea.status, .todo)
    }

    @MainActor
    func testScopeSnapshotIsTheSingleSourceForSectionsAndCounts() throws {
        let store = try makeTestStore()
        _ = store.create(title: "Todo")
        _ = store.create(title: "Progress")
        _ = store.create(title: "Done")
        _ = store.create(title: "Idea", status: .backlog)
        let progress = try XCTUnwrap(store.tasks.first { $0.title == "Progress" })
        let done = try XCTUnwrap(store.tasks.first { $0.title == "Done" })
        store.setStatus(.inProgress, for: progress)
        store.setStatus(.done, for: done)

        let taskSnapshot = store.snapshot(for: .tasks)
        XCTAssertEqual(taskSnapshot.visibleCount, 3)
        XCTAssertEqual(taskSnapshot.activeCount, 2)
        XCTAssertEqual(taskSnapshot.sections.map(\.status), [.inProgress, .todo, .done])

        let backlogSnapshot = store.snapshot(for: .backlog)
        XCTAssertEqual(backlogSnapshot.visibleCount, 1)
        XCTAssertEqual(backlogSnapshot.activeCount, 1)
        XCTAssertEqual(backlogSnapshot.sections.map(\.status), [.backlog])
    }

    @MainActor
    func testReorderWithinSameStatusAndPriorityPersists() throws {
        let clock = MutableNow(Date(timeIntervalSince1970: 1_000))
        let store = try makeTestStore(now: { clock.value })
        let first = try XCTUnwrap(store.create(title: "First", priority: .medium))
        clock.value = Date(timeIntervalSince1970: 1_100)
        let second = try XCTUnwrap(store.create(title: "Second", priority: .medium))
        clock.value = Date(timeIntervalSince1970: 1_200)
        let third = try XCTUnwrap(store.create(title: "Third", priority: .medium))

        XCTAssertEqual(store.orderedTasks(for: .todo).map(\.id), [third.id, second.id, first.id])
        XCTAssertTrue(store.reorder(taskID: third.id, relativeTo: first.id))
        XCTAssertEqual(store.orderedTasks(for: .todo).map(\.id), [second.id, first.id, third.id])

        clock.value = Date(timeIntervalSince1970: 1_300)
        store.rename(third, to: "Third renamed")
        XCTAssertEqual(store.orderedTasks(for: .todo).map(\.id), [second.id, first.id, third.id])

        clock.value = Date(timeIntervalSince1970: 1_400)
        let newest = try XCTUnwrap(store.create(title: "Newest", priority: .medium))
        XCTAssertEqual(store.orderedTasks(for: .todo).map(\.id), [newest.id, second.id, first.id, third.id])

        store.refresh()
        XCTAssertEqual(store.orderedTasks(for: .todo).map(\.id), [newest.id, second.id, first.id, third.id])
    }

    @MainActor
    func testReorderRejectsIncompatibleAndDegenerateDrops() throws {
        let store = try makeTestStore()
        let medium = try XCTUnwrap(store.create(title: "Medium", priority: .medium))
        let high = try XCTUnwrap(store.create(title: "High", priority: .high))
        let anotherMedium = try XCTUnwrap(store.create(title: "Another", priority: .medium))
        store.setStatus(.inProgress, for: anotherMedium)

        XCTAssertFalse(store.reorder(taskID: medium.id, relativeTo: medium.id))
        XCTAssertFalse(store.reorder(taskID: medium.id, relativeTo: high.id))
        XCTAssertFalse(store.reorder(taskID: medium.id, relativeTo: anotherMedium.id))
        XCTAssertFalse(store.reorder(taskID: UUID(), relativeTo: medium.id))
    }
}
