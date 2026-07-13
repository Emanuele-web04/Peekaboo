import XCTest
import SwiftData
@testable import Peekaboo

final class DailyCleanupServiceTests: XCTestCase {
    @MainActor
    func testCleanupDeletesOnlyDoneTasksFromEarlierDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Rome"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 9)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let clock = MutableNow(yesterday)
        let store = try makeTestStore(now: { clock.value })

        let oldDone = try XCTUnwrap(store.create(title: "Old done"))
        store.markDone(oldDone)
        let pending = try XCTUnwrap(store.create(title: "Still todo"))
        let progressing = try XCTUnwrap(store.create(title: "Still progressing"))
        store.setStatus(.inProgress, for: progressing)

        clock.value = now
        let todayDone = try XCTUnwrap(store.create(title: "Today done"))
        store.markDone(todayDone)

        let service = DailyCleanupService(store: store, now: { now }, calendar: { calendar })
        XCTAssertEqual(service.performCleanup(), 1)

        XCTAssertFalse(store.tasks.contains { $0.id == oldDone.id })
        XCTAssertTrue(store.tasks.contains { $0.id == todayDone.id })
        XCTAssertTrue(store.tasks.contains { $0.id == pending.id })
        XCTAssertTrue(store.tasks.contains { $0.id == progressing.id })
    }

    @MainActor
    func testTaskCompletedJustBeforeMidnightExpiresAfterDayChange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Rome"))
        let beforeMidnight = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 8, hour: 23, minute: 59))
        )
        let afterMidnight = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 9, hour: 0, minute: 1))
        )
        let clock = MutableNow(beforeMidnight)
        let store = try makeTestStore(now: { clock.value })
        let task = try XCTUnwrap(store.create(title: "Late finish"))
        store.markDone(task)

        clock.value = afterMidnight
        let service = DailyCleanupService(store: store, now: { clock.value }, calendar: { calendar })
        XCTAssertEqual(service.performCleanup(), 1)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    @MainActor
    func testCleanupPreservesDivergentDuplicateButDeletesOldDoneAfterRecentEdit() throws {
        let now = Date(timeIntervalSince1970: 500_000)
        let old = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let sharedID = UUID()
        context.insert(TaskItem(
            id: sharedID,
            title: "Done copy",
            status: .done,
            createdAt: old,
            updatedAt: old,
            completedAt: old
        ))
        context.insert(TaskItem(
            id: sharedID,
            title: "Restored copy",
            status: .todo,
            createdAt: old,
            updatedAt: now
        ))
        let recentDone = TaskItem(
            title: "Recently edited",
            status: .done,
            createdAt: old,
            updatedAt: now,
            completedAt: old
        )
        context.insert(recentDone)
        try context.save()

        let store = TaskStore(container: container)
        let service = DailyCleanupService(store: store, now: { now })

        XCTAssertEqual(service.performCleanup(), 1)
        let verificationContext = ModelContext(container)
        let remaining = try verificationContext.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(remaining.count, 2)
        XCTAssertTrue(remaining.allSatisfy { $0.id == sharedID })
    }

    @MainActor
    func testCleanupPreservesDoneReplicasWithDivergentFields() throws {
        let now = Date(timeIntervalSince1970: 500_000)
        let old = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let sharedID = UUID()
        context.insert(TaskItem(
            id: sharedID,
            title: "Original title",
            status: .done,
            priority: .low,
            createdAt: old,
            updatedAt: old,
            completedAt: old
        ))
        context.insert(TaskItem(
            id: sharedID,
            title: "Conflicting title",
            status: .done,
            priority: .high,
            createdAt: old,
            updatedAt: old,
            completedAt: old
        ))
        try context.save()

        let store = TaskStore(container: container)
        let service = DailyCleanupService(store: store, now: { now })

        XCTAssertEqual(service.performCleanup(), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 2)
    }
}
