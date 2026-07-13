import XCTest
import SwiftData
import UniformTypeIdentifiers
@testable import Peekaboo

final class TaskStoreTests: XCTestCase {
    @MainActor
    func testAgentAccessRequiresExplicitOptInOnlyOnce() {
        let suiteName = "PeekabooTests.AgentAccess.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let initialSettings = AppSettings(defaults: defaults)
        XCTAssertFalse(initialSettings.isAgentAccessEnabled)

        initialSettings.isAgentAccessEnabled = true
        let reloadedSettings = AppSettings(defaults: defaults)
        XCTAssertTrue(reloadedSettings.isAgentAccessEnabled)
    }

    func testTaskDragPayloadExportsInternalDataAndPlainText() {
        let taskID = UUID()
        let payload = TaskDragPayload(taskID: taskID, title: "Paste me")
        let provider = payload.itemProvider()

        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.text.identifier))
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(
            TaskDragPayload.internalTaskType.identifier
        ))

        let internalIDLoaded = expectation(description: "Internal task identity loads")
        XCTAssertTrue(TaskDragPayload.loadTaskID(from: [provider]) { loadedID in
            XCTAssertEqual(loadedID, taskID)
            internalIDLoaded.fulfill()
        })

        let plainTextLoaded = expectation(description: "Plain-text drag representation loads")
        provider.loadDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier) { data, error in
            XCTAssertNil(error)
            XCTAssertEqual(data, Data("Paste me".utf8))
            plainTextLoaded.fulfill()
        }
        wait(for: [internalIDLoaded, plainTextLoaded], timeout: 1)

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
        let gate = PersistenceGate()
        gate.shouldFail = true
        let store = try makeTestStore(persist: gate.save)

        XCTAssertNil(store.create(title: "Must not disappear"))
        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertNotNil(store.lastErrorMessage)
    }

    @MainActor
    func testRefreshSeesChangesSavedByAnotherModelContext() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = TaskStore(container: container)
        let externalContext = ModelContext(container)
        let externalTask = TaskItem(title: "Created elsewhere", priority: .low)

        externalContext.insert(externalTask)
        try externalContext.save()
        store.refresh()

        let imported = try XCTUnwrap(store.tasks.first)
        XCTAssertEqual(imported.id, externalTask.id)
        XCTAssertEqual(imported.title, "Created elsewhere")

        externalTask.title = "Updated elsewhere"
        externalTask.updatedAt = Date(timeIntervalSince1970: 2_000)
        try externalContext.save()
        store.refresh()

        XCTAssertEqual(try XCTUnwrap(store.tasks.first).title, "Updated elsewhere")
    }

    @MainActor
    func testSuccessfulCloudImportRefreshesChangesSavedOutsideStoreContext() async throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let seedContext = ModelContext(container)
        seedContext.insert(TaskItem(title: "Before iPhone update", priority: .high))
        try seedContext.save()

        let store = TaskStore(container: container)
        XCTAssertEqual(store.tasks.map(\.title), ["Before iPhone update"])

        let externalContext = ModelContext(container)
        let importedTask = try XCTUnwrap(
            externalContext.fetch(FetchDescriptor<TaskItem>()).first
        )
        importedTask.title = "Updated from iPhone"
        importedTask.updatedAt = Date()
        try externalContext.save()
        XCTAssertEqual(store.tasks.map(\.title), ["Before iPhone update"])

        store.handleCloudSyncEvent(CloudSyncEventUpdate(
            id: UUID(),
            kind: .importData,
            endedAt: Date(),
            succeeded: true,
            errorMessage: nil
        ))
        try await Task.sleep(for: .milliseconds(250))

        XCTAssertEqual(store.tasks.map(\.title), ["Updated from iPhone"])
    }

    @MainActor
    func testRefreshHidesDuplicateApplicationIDsWithoutDeletingEitherRow() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let sharedID = UUID()
        let older = TaskItem(
            id: sharedID,
            title: "Older",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let newer = TaskItem(
            id: sharedID,
            title: "Newer",
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        context.insert(older)
        context.insert(newer)
        try context.save()

        let store = TaskStore(container: container)

        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks.first?.title, "Newer")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 2)
    }

    @MainActor
    func testEqualTimestampDuplicatesAreHiddenWithoutCrossDeviceDeletion() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let sharedID = UUID()
        let timestamp = Date(timeIntervalSince1970: 2_000)
        context.insert(TaskItem(id: sharedID, title: "Alpha", updatedAt: timestamp))
        context.insert(TaskItem(id: sharedID, title: "Beta", updatedAt: timestamp))
        try context.save()

        let store = TaskStore(container: container)

        XCTAssertEqual(store.tasks.map(\.title), ["Beta"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 2)
        store.refresh()
        XCTAssertEqual(store.tasks.map(\.title), ["Beta"])
    }

    @MainActor
    func testMutationsAndDeleteApplyToEveryPhysicalDuplicate() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let seedContext = ModelContext(container)
        let sharedID = UUID()
        seedContext.insert(TaskItem(id: sharedID, title: "Older", priority: .low))
        seedContext.insert(TaskItem(
            id: sharedID,
            title: "Visible",
            priority: .medium,
            updatedAt: Date().addingTimeInterval(1)
        ))
        try seedContext.save()
        let store = TaskStore(container: container)
        let visible = try XCTUnwrap(store.tasks.first)

        XCTAssertTrue(store.update(visible, title: "Unified", priority: .high, status: .done))
        var verificationContext = ModelContext(container)
        var replicas = try verificationContext.fetch(FetchDescriptor<TaskItem>())
        XCTAssertEqual(replicas.count, 2)
        XCTAssertTrue(replicas.allSatisfy {
            $0.title == "Unified"
                && $0.priority == .high
                && $0.status == .done
                && $0.completedAt != nil
        })

        XCTAssertTrue(store.delete(try XCTUnwrap(store.tasks.first)))
        verificationContext = ModelContext(container)
        replicas = try verificationContext.fetch(FetchDescriptor<TaskItem>())
        XCTAssertTrue(replicas.isEmpty)
    }

    @MainActor
    func testExactDuplicateSelectionStaysStableAcrossRefreshes() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let seedContext = ModelContext(container)
        let sharedID = UUID()
        let timestamp = Date(timeIntervalSince1970: 2_000)
        seedContext.insert(TaskItem(id: sharedID, title: "Same", updatedAt: timestamp))
        seedContext.insert(TaskItem(id: sharedID, title: "Same", updatedAt: timestamp))
        try seedContext.save()
        let store = TaskStore(container: container)
        let selectedID = try XCTUnwrap(store.tasks.first?.persistentModelID)

        for _ in 0..<5 {
            store.refresh()
            XCTAssertEqual(store.tasks.first?.persistentModelID, selectedID)
        }
    }

    @MainActor
    func testRemoteDeletionMakesCapturedTaskReferencesNoOps() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = TaskStore(container: container)
        let capturedTask = try XCTUnwrap(store.create(title: "Deleted elsewhere"))
        let externalContext = ModelContext(container)
        let externalTask = try XCTUnwrap(
            try externalContext.fetch(FetchDescriptor<TaskItem>()).first
        )
        externalContext.delete(externalTask)
        try externalContext.save()
        store.refresh()

        XCTAssertTrue(store.tasks.isEmpty)
        XCTAssertFalse(store.update(capturedTask, title: "Resurrected"))
        XCTAssertFalse(store.delete(capturedTask))
        XCTAssertFalse(store.performPrimaryAction(capturedTask))
    }

    @MainActor
    func testRefreshNeverPersistsDuplicateCleanup() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let sharedID = UUID()
        context.insert(TaskItem(id: sharedID, title: "Older"))
        context.insert(TaskItem(id: sharedID, title: "Newer", updatedAt: Date().addingTimeInterval(1)))
        try context.save()

        let gate = PersistenceGate()
        gate.shouldFail = true
        let store = TaskStore(container: container, persist: gate.save)

        XCTAssertEqual(store.tasks.map(\.title), ["Newer"])
        XCTAssertNil(store.lastErrorMessage)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TaskItem>()), 2)
    }

    func testCloudConfigurationsUseSeparateEnvironmentStores() {
        let legacy = ModelConfiguration(isStoredInMemoryOnly: false)
        let production = PersistenceController.makeConfiguration(environment: .production)
        let development = PersistenceController.makeConfiguration(environment: .development)
        let inMemory = PersistenceController.makeConfiguration(inMemory: true)

        XCTAssertEqual(production.url, legacy.url)
        XCTAssertNotEqual(development.url, production.url)
        XCTAssertEqual(development.url.lastPathComponent, "development.store")
        XCTAssertEqual(
            production.cloudKitContainerIdentifier,
            PersistenceController.cloudKitContainerIdentifier
        )
        XCTAssertEqual(
            development.cloudKitContainerIdentifier,
            PersistenceController.cloudKitContainerIdentifier
        )
        XCTAssertNil(inMemory.cloudKitContainerIdentifier)
    }

    func testDevelopmentFallbackWithoutCloudKitKeepsDevelopmentStore() {
        let production = PersistenceController.makeConfiguration(
            cloudSyncEnabled: false,
            environment: .production
        )
        let development = PersistenceController.makeConfiguration(
            cloudSyncEnabled: false,
            environment: .development
        )

        XCTAssertEqual(production.url.lastPathComponent, "default.store")
        XCTAssertEqual(development.url.lastPathComponent, "development.store")
        XCTAssertNil(production.cloudKitContainerIdentifier)
        XCTAssertNil(development.cloudKitContainerIdentifier)
    }

    @MainActor
    func testFailedEditsRestorePersistedValues() throws {
        let gate = PersistenceGate()
        let store = try makeTestStore(persist: gate.save)
        let task = try XCTUnwrap(store.create(title: "Original", priority: .low))
        gate.shouldFail = true

        XCTAssertFalse(store.rename(task, to: "Changed"))
        XCTAssertEqual(try XCTUnwrap(store.tasks.first).title, "Original")

        let afterRename = try XCTUnwrap(store.tasks.first)
        XCTAssertFalse(store.setPriority(.high, for: afterRename))
        XCTAssertEqual(try XCTUnwrap(store.tasks.first).priority, .low)

        let afterPriority = try XCTUnwrap(store.tasks.first)
        XCTAssertFalse(store.setStatus(.done, for: afterPriority))
        let restored = try XCTUnwrap(store.tasks.first)
        XCTAssertEqual(restored.status, .todo)
        XCTAssertNil(restored.completedAt)
    }

    @MainActor
    func testAtomicUpdateRollsBackEveryFieldOnPersistenceFailure() throws {
        let gate = PersistenceGate()
        let store = try makeTestStore(persist: gate.save)
        let task = try XCTUnwrap(store.create(title: "Original", priority: .low))
        gate.shouldFail = true

        XCTAssertFalse(store.update(task, title: "Changed", priority: .high, status: .done))

        let restored = try XCTUnwrap(store.tasks.first)
        XCTAssertEqual(restored.title, "Original")
        XCTAssertEqual(restored.priority, .low)
        XCTAssertEqual(restored.status, .todo)
        XCTAssertNil(restored.completedAt)
    }

    @MainActor
    func testFailedDeleteRestoresTask() throws {
        let gate = PersistenceGate()
        let store = try makeTestStore(persist: gate.save)
        let task = try XCTUnwrap(store.create(title: "Keep me"))
        gate.shouldFail = true

        XCTAssertFalse(store.delete(task))
        XCTAssertEqual(store.tasks.map(\.title), ["Keep me"])
    }

    @MainActor
    func testFailedReorderRestoresOriginalOrder() throws {
        let gate = PersistenceGate()
        let clock = MutableNow(Date(timeIntervalSince1970: 1_000))
        let store = try makeTestStore(now: { clock.value }, persist: gate.save)
        let first = try XCTUnwrap(store.create(title: "First", priority: .medium))
        clock.value = Date(timeIntervalSince1970: 1_100)
        let second = try XCTUnwrap(store.create(title: "Second", priority: .medium))
        XCTAssertEqual(store.orderedTasks(for: .todo).map(\.id), [second.id, first.id])
        gate.shouldFail = true

        XCTAssertFalse(store.reorder(taskID: second.id, relativeTo: first.id))
        XCTAssertEqual(store.orderedTasks(for: .todo).map(\.title), ["Second", "First"])
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
    func testCreatingDoneTaskSetsCompletionDate() throws {
        let timestamp = Date(timeIntervalSince1970: 1_500)
        let store = try makeTestStore(now: { timestamp })

        let task = try XCTUnwrap(store.create(title: "Already finished", status: .done))

        XCTAssertEqual(task.completedAt, timestamp)
    }

    @MainActor
    func testPartialEditFromStaleReferencePreservesImportedFields() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let store = TaskStore(container: container)
        let capturedTask = try XCTUnwrap(store.create(title: "Original", priority: .low))

        let externalContext = ModelContext(container)
        let importedTask = try XCTUnwrap(
            externalContext.fetch(FetchDescriptor<TaskItem>()).first
        )
        importedTask.priority = .high
        importedTask.status = .done
        importedTask.completedAt = Date(timeIntervalSince1970: 2_000)
        importedTask.updatedAt = Date(timeIntervalSince1970: 2_000)
        try externalContext.save()
        store.refresh()

        XCTAssertTrue(store.update(capturedTask, title: "Renamed locally"))
        let saved = try XCTUnwrap(store.tasks.first)
        XCTAssertEqual(saved.title, "Renamed locally")
        XCTAssertEqual(saved.priority, .high)
        XCTAssertEqual(saved.status, .done)
        XCTAssertEqual(saved.completedAt, Date(timeIntervalSince1970: 2_000))
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
    func testSnapshotMemoizationStaysCoherentAcrossMutations() throws {
        let store = try makeTestStore()
        let task = try XCTUnwrap(store.create(title: "Cached"))

        XCTAssertEqual(store.snapshot(for: .tasks).visibleCount, 1)
        // Second call between edits must serve the same content (cache hit).
        XCTAssertEqual(store.snapshot(for: .tasks).sections.map(\.status), [.todo])

        store.setStatus(.inProgress, for: task)
        XCTAssertEqual(store.snapshot(for: .tasks).sections.map(\.status), [.inProgress])

        store.setStatus(.backlog, for: task)
        XCTAssertEqual(store.snapshot(for: .tasks).visibleCount, 0)
        XCTAssertEqual(store.snapshot(for: .backlog).visibleCount, 1)

        store.delete(task)
        XCTAssertEqual(store.snapshot(for: .backlog).visibleCount, 0)

        store.refresh()
        XCTAssertEqual(store.snapshot(for: .backlog).visibleCount, 0)
    }

    @MainActor
    func testExternalDragStartsPendingTasksWithoutReopeningDoneTasks() throws {
        let store = try makeTestStore()
        let todo = try XCTUnwrap(store.create(title: "Todo"))
        let backlog = try XCTUnwrap(store.create(title: "Idea", status: .backlog))
        let inProgress = try XCTUnwrap(store.create(title: "Working", status: .inProgress))
        let done = try XCTUnwrap(store.create(title: "Finished", status: .done))

        XCTAssertTrue(store.startAfterExternalDrag(taskID: todo.id))
        XCTAssertEqual(todo.status, .inProgress)

        XCTAssertTrue(store.startAfterExternalDrag(taskID: backlog.id))
        XCTAssertEqual(backlog.status, .inProgress)

        XCTAssertTrue(store.startAfterExternalDrag(taskID: inProgress.id))
        XCTAssertEqual(inProgress.status, .inProgress)

        XCTAssertFalse(store.startAfterExternalDrag(taskID: done.id))
        XCTAssertEqual(done.status, .done)
        XCTAssertFalse(store.startAfterExternalDrag(taskID: UUID()))
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

        let firstOrder = first.manualOrder
        let secondOrder = second.manualOrder
        XCTAssertTrue(store.reorder(taskID: third.id, relativeTo: second.id))
        XCTAssertEqual(first.manualOrder, firstOrder)
        XCTAssertEqual(second.manualOrder, secondOrder)
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
    func testDropOntoRowReordersWithinSectionAndRestatusesAcrossSections() throws {
        let clock = MutableNow(Date(timeIntervalSince1970: 1_000))
        let store = try makeTestStore(now: { clock.value })
        let first = try XCTUnwrap(store.create(title: "First"))
        clock.value = Date(timeIntervalSince1970: 1_100)
        let second = try XCTUnwrap(store.create(title: "Second"))
        clock.value = Date(timeIntervalSince1970: 1_200)
        let finished = try XCTUnwrap(store.create(title: "Finished", status: .done))

        // Same section behaves like a plain reorder.
        XCTAssertTrue(store.drop(taskID: second.id, onto: first.id))
        XCTAssertEqual(store.orderedTasks(for: .todo).map(\.id), [first.id, second.id])

        // Another section's row: the task adopts that section's status and
        // lands next to the target row.
        clock.value = Date(timeIntervalSince1970: 1_300)
        XCTAssertTrue(store.drop(taskID: first.id, onto: finished.id))
        XCTAssertEqual(first.status, .done)
        XCTAssertNotNil(first.completedAt)
        XCTAssertEqual(store.orderedTasks(for: .done).map(\.id), [finished.id, first.id])
        XCTAssertEqual(store.orderedTasks(for: .todo).map(\.id), [second.id])

        // A cross-section drop keeps the dragged task's own priority.
        clock.value = Date(timeIntervalSince1970: 1_400)
        let urgent = try XCTUnwrap(store.create(title: "Urgent", priority: .high))
        XCTAssertTrue(store.drop(taskID: urgent.id, onto: finished.id))
        XCTAssertEqual(urgent.status, .done)
        XCTAssertEqual(urgent.priority, .high)

        XCTAssertFalse(store.drop(taskID: second.id, onto: second.id))
        XCTAssertFalse(store.drop(taskID: UUID(), onto: second.id))
        XCTAssertFalse(store.drop(taskID: second.id, onto: UUID()))
    }

    @MainActor
    func testDropIntoSectionChangesStatusOnlyAcrossSections() throws {
        let store = try makeTestStore()
        let task = try XCTUnwrap(store.create(title: "Task"))

        XCTAssertTrue(store.drop(taskID: task.id, into: .inProgress))
        XCTAssertEqual(task.status, .inProgress)

        XCTAssertTrue(store.drop(taskID: task.id, into: .done))
        XCTAssertEqual(task.status, .done)
        XCTAssertNotNil(task.completedAt)

        // Dropping back into the section it already lives in is a no-op.
        XCTAssertFalse(store.drop(taskID: task.id, into: .done))
        XCTAssertFalse(store.drop(taskID: UUID(), into: .todo))
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

    @MainActor
    func testRebalanceUpdatesManualOrderOnEveryPhysicalReplica() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let firstTimestamp = Date(timeIntervalSince1970: 1_000)
        let secondTimestamp = Date(timeIntervalSince1970: 2_000)
        let thirdTimestamp = Date(timeIntervalSince1970: 3_000)

        context.insert(TaskItem(
            id: firstID,
            title: "First",
            priority: .medium,
            createdAt: firstTimestamp,
            updatedAt: firstTimestamp,
            manualOrder: 1
        ))
        context.insert(TaskItem(
            id: firstID,
            title: "First",
            priority: .medium,
            createdAt: firstTimestamp,
            updatedAt: firstTimestamp,
            manualOrder: 1
        ))
        context.insert(TaskItem(
            id: secondID,
            title: "Second",
            priority: .medium,
            createdAt: secondTimestamp,
            updatedAt: secondTimestamp,
            manualOrder: 1
        ))
        context.insert(TaskItem(
            id: thirdID,
            title: "Third",
            priority: .medium,
            createdAt: thirdTimestamp,
            updatedAt: thirdTimestamp,
            manualOrder: 1
        ))
        try context.save()
        let store = TaskStore(container: container)

        XCTAssertTrue(store.reorder(taskID: firstID, relativeTo: secondID))

        let verificationContext = ModelContext(container)
        let replicas = try verificationContext.fetch(FetchDescriptor<TaskItem>())
        let firstOrders = Set(replicas.filter { $0.id == firstID }.map(\.manualOrder))
        XCTAssertEqual(firstOrders.count, 1)
        XCTAssertEqual(Set(replicas.compactMap(\.manualOrder)).count, 3)
    }

    func testCloudSyncStatusTracksActivitySuccessAndFailure() {
        let importID = UUID()
        let exportID = UUID()
        let importEnd = Date(timeIntervalSince1970: 1_000)
        let exportEnd = Date(timeIntervalSince1970: 2_000)
        var status = CloudSyncStatus()

        status.apply(CloudSyncEventUpdate(
            id: importID,
            kind: .importData,
            endedAt: nil,
            succeeded: false,
            errorMessage: nil
        ))
        XCTAssertTrue(status.isSyncing)
        XCTAssertEqual(status.title, "Syncing…")

        status.apply(CloudSyncEventUpdate(
            id: importID,
            kind: .importData,
            endedAt: importEnd,
            succeeded: true,
            errorMessage: nil
        ))
        XCTAssertFalse(status.isSyncing)
        XCTAssertEqual(status.lastSuccessfulImportAt, importEnd)
        XCTAssertEqual(status.title, "Synced")

        status.apply(CloudSyncEventUpdate(
            id: exportID,
            kind: .exportData,
            endedAt: exportEnd,
            succeeded: false,
            errorMessage: "Quota exceeded"
        ))
        XCTAssertEqual(status.lastErrorMessage, "Quota exceeded")
        XCTAssertEqual(status.title, "Sync issue")

        status.apply(CloudSyncEventUpdate(
            id: UUID(),
            kind: .importData,
            endedAt: exportEnd.addingTimeInterval(1),
            succeeded: true,
            errorMessage: nil
        ))
        XCTAssertEqual(status.lastErrorMessage, "Quota exceeded")

        status.apply(CloudSyncEventUpdate(
            id: exportID,
            kind: .exportData,
            endedAt: exportEnd.addingTimeInterval(2),
            succeeded: true,
            errorMessage: nil
        ))
        XCTAssertNil(status.lastErrorMessage)
        XCTAssertEqual(status.title, "Synced")
    }

    func testCloudSyncProtectionKeepsNewerSaveProtectedFromOlderExport() {
        let firstExportID = UUID()
        let secondExportID = UUID()
        var protection = CloudSyncProtectionState()

        protection.noteLocalSave()
        protection.apply(CloudSyncEventUpdate(
            id: firstExportID,
            kind: .exportData,
            endedAt: nil,
            succeeded: false,
            errorMessage: nil
        ))
        protection.noteLocalSave()
        protection.apply(CloudSyncEventUpdate(
            id: secondExportID,
            kind: .exportData,
            endedAt: nil,
            succeeded: false,
            errorMessage: nil
        ))
        protection.apply(CloudSyncEventUpdate(
            id: firstExportID,
            kind: .exportData,
            endedAt: Date(),
            succeeded: true,
            errorMessage: nil
        ))

        XCTAssertTrue(protection.protectsExport)

        protection.apply(CloudSyncEventUpdate(
            id: secondExportID,
            kind: .exportData,
            endedAt: Date(),
            succeeded: true,
            errorMessage: nil
        ))
        XCTAssertFalse(protection.protectsExport)
    }

    func testCloudSyncProtectionKeepsOverlappingImportsProtectedUntilRefresh() {
        let firstImportID = UUID()
        let secondImportID = UUID()
        var protection = CloudSyncProtectionState()

        for id in [firstImportID, secondImportID] {
            protection.apply(CloudSyncEventUpdate(
                id: id,
                kind: .importData,
                endedAt: nil,
                succeeded: false,
                errorMessage: nil
            ))
        }
        protection.apply(CloudSyncEventUpdate(
            id: firstImportID,
            kind: .importData,
            endedAt: Date(),
            succeeded: true,
            errorMessage: nil
        ))
        protection.completeImportRefresh()
        XCTAssertTrue(protection.protectsImport)

        protection.apply(CloudSyncEventUpdate(
            id: secondImportID,
            kind: .importData,
            endedAt: Date(),
            succeeded: true,
            errorMessage: nil
        ))
        XCTAssertTrue(protection.protectsImport)
        protection.completeImportRefresh()
        XCTAssertFalse(protection.protectsImport)
    }
}
