import Combine
import CoreData
import Foundation
import SwiftData

struct TaskSectionSnapshot: Identifiable {
    let status: TaskStatus
    let tasks: [TaskItem]

    var id: TaskStatus { status }
}

struct TaskScopeSnapshot {
    let sections: [TaskSectionSnapshot]
    let visibleCount: Int
    let activeCount: Int
}

enum CloudSyncActivityKind: Equatable {
    case setup
    case importData
    case exportData
}

struct CloudSyncEventUpdate: Equatable {
    let id: UUID
    let kind: CloudSyncActivityKind
    let endedAt: Date?
    let succeeded: Bool
    let errorMessage: String?
}

struct CloudSyncStatus: Equatable {
    private(set) var activeEventIDs: Set<UUID> = []
    private(set) var lastSuccessfulImportAt: Date?
    private(set) var lastSuccessfulExportAt: Date?
    private(set) var lastErrorMessage: String?
    private var lastErrorKind: CloudSyncActivityKind?

    var isSyncing: Bool { !activeEventIDs.isEmpty }

    var lastSuccessfulActivityAt: Date? {
        [lastSuccessfulImportAt, lastSuccessfulExportAt]
            .compactMap { $0 }
            .max()
    }

    var title: String {
        if isSyncing { return "Syncing…" }
        if lastErrorMessage != nil { return "Sync issue" }
        if lastSuccessfulActivityAt != nil { return "Synced" }
        return "Waiting for iCloud"
    }

    var symbolName: String {
        if isSyncing { return "arrow.triangle.2.circlepath.icloud" }
        if lastErrorMessage != nil { return "exclamationmark.icloud" }
        if lastSuccessfulActivityAt != nil { return "checkmark.icloud" }
        return "icloud"
    }

    mutating func apply(_ update: CloudSyncEventUpdate) {
        guard let endedAt = update.endedAt else {
            activeEventIDs.insert(update.id)
            return
        }

        activeEventIDs.remove(update.id)
        if update.succeeded {
            switch update.kind {
            case .setup:
                break
            case .importData:
                lastSuccessfulImportAt = endedAt
            case .exportData:
                lastSuccessfulExportAt = endedAt
            }
            if lastErrorKind == update.kind {
                lastErrorMessage = nil
                lastErrorKind = nil
            }
        } else {
            lastErrorMessage = update.errorMessage ?? "iCloud couldn't complete the sync operation."
            lastErrorKind = update.kind
        }
    }
}

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var cloudSyncStatus = CloudSyncStatus()

    private let container: ModelContainer
    private var context: ModelContext
    private let now: () -> Date
    private let persist: (ModelContext) throws -> Void
    private var remoteChangeObservation: AnyCancellable?
    private var cloudKitEventObservation: AnyCancellable?
    private var cloudImportRefreshTask: Task<Void, Never>?
#if os(macOS)
    private var exportActivityToken: NSObjectProtocol?
    private var importActivityToken: NSObjectProtocol?
    private var exportActivityTimeoutTask: Task<Void, Never>?
    private var importActivityTimeoutTask: Task<Void, Never>?
#endif
    private var snapshotCache: [TaskScope: (revision: UInt64, snapshot: TaskScopeSnapshot)] = [:]
    private static let manualOrderStride: Int64 = 1_024
#if os(macOS)
    private static let cloudSyncActivityTimeout: Duration = .seconds(120)
#endif

    init(
        container: ModelContainer,
        now: @escaping () -> Date = Date.init,
        persist: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.container = container
        context = ModelContext(container)
        self.now = now
        self.persist = persist
        refresh()
        observeRemoteChanges()
        observeCloudKitEvents()
    }

    @discardableResult
    func create(
        title: String,
        priority: TaskPriority = .none,
        status: TaskStatus = .todo
    ) -> TaskItem? {
        let normalizedTitle = Self.normalized(title)
        guard !normalizedTitle.isEmpty else { return nil }

        let timestamp = now()
        let task = TaskItem(
            title: normalizedTitle,
            status: status,
            priority: priority,
            createdAt: timestamp,
            manualOrder: nextManualOrder(status: status, priority: priority)
        )
        context.insert(task)
        tasks.append(task)
        guard save() else { return nil }
        return task
    }

    @discardableResult
    func rename(_ task: TaskItem, to title: String) -> Bool {
        update(task, title: title)
    }

    @discardableResult
    func setPriority(_ priority: TaskPriority, for task: TaskItem) -> Bool {
        update(task, priority: priority)
    }

    @discardableResult
    func setStatus(_ status: TaskStatus, for task: TaskItem) -> Bool {
        update(task, status: status)
    }

    /// Applies a task edit as one SwiftData transaction so callers never see
    /// a partially persisted title, priority, or status change.
    @discardableResult
    func update(
        _ task: TaskItem,
        title: String? = nil,
        priority: TaskPriority? = nil,
        status: TaskStatus? = nil
    ) -> Bool {
        guard let task = tasks.first(where: { $0.id == task.id }) else { return false }
        let replicas = storedTasks(matching: task.id, fallback: task)
        let normalizedTitle = title.map(Self.normalized)
        if let normalizedTitle, normalizedTitle.isEmpty { return false }

        let destinationTitle = normalizedTitle ?? task.title
        let destinationPriority = priority ?? task.priority
        let destinationStatus = status ?? task.status
        let titleChanged = destinationTitle != task.title
        let priorityChanged = destinationPriority != task.priority
        let statusChanged = destinationStatus != task.status
        let replicasNeedRepair = replicas.contains {
            $0.title != task.title
                || $0.priority != task.priority
                || $0.status != task.status
                || $0.completedAt != task.completedAt
                || $0.manualOrder != task.manualOrder
        }
        guard titleChanged || priorityChanged || statusChanged || replicasNeedRepair else {
            return true
        }

        let timestamp = now()
        let destinationManualOrder: Int64?
        if priorityChanged || statusChanged {
            destinationManualOrder = nextManualOrder(
                status: destinationStatus,
                priority: destinationPriority,
                excluding: task.id
            )
        } else {
            destinationManualOrder = task.manualOrder
        }
        let destinationCompletedAt: Date?
        if statusChanged {
            destinationCompletedAt = destinationStatus == .done ? timestamp : nil
        } else {
            destinationCompletedAt = task.completedAt
        }

        for replica in replicas {
            replica.title = destinationTitle
            replica.priority = destinationPriority
            replica.status = destinationStatus
            replica.manualOrder = destinationManualOrder
            replica.completedAt = destinationCompletedAt
            replica.updatedAt = timestamp
        }
        return save()
    }

    @discardableResult
    func advanceToInProgress(_ task: TaskItem) -> Bool {
        guard let task = tasks.first(where: { $0.id == task.id }) else { return false }
        guard task.status == .todo else { return false }
        return setStatus(.inProgress, for: task)
    }

    @discardableResult
    func performDoubleClickAction(_ task: TaskItem) -> Bool {
        guard let task = tasks.first(where: { $0.id == task.id }) else { return false }
        guard let destination = task.status.doubleClickDestination else { return false }
        return setStatus(destination, for: task)
    }

    @discardableResult
    func markDone(_ task: TaskItem) -> Bool {
        guard let task = tasks.first(where: { $0.id == task.id }) else { return false }
        guard task.status != .done else { return true }
        return setStatus(.done, for: task)
    }

    @discardableResult
    func performPrimaryAction(_ task: TaskItem) -> Bool {
        guard let task = tasks.first(where: { $0.id == task.id }) else { return false }
        return setStatus(task.status.primaryActionDestination, for: task)
    }

    @discardableResult
    func delete(_ task: TaskItem) -> Bool {
        guard let task = tasks.first(where: { $0.id == task.id }) else { return false }
        storedTasks(matching: task.id, fallback: task).forEach(context.delete)
        tasks.removeAll { $0.id == task.id }
        return save()
    }

    @discardableResult
    func purgeCompleted(before cutoff: Date) -> Int {
        let stored: [TaskItem]
        do {
            stored = try context.fetch(FetchDescriptor<TaskItem>())
        } catch {
            lastErrorMessage = error.localizedDescription
            return 0
        }

        let grouped = Dictionary(grouping: stored, by: \.id)
        let expiredIDs = Set(grouped.compactMap { id, replicas -> UUID? in
            let everyReplicaExpired = replicas.allSatisfy { task in
                task.status == .done
                    && task.completedAt.map { $0 < cutoff } == true
            }
            return everyReplicaExpired ? id : nil
        })
        guard !expiredIDs.isEmpty else { return 0 }
        stored.filter { expiredIDs.contains($0.id) }.forEach(context.delete)
        tasks.removeAll { expiredIDs.contains($0.id) }
        return save() ? expiredIDs.count : 0
    }

    func orderedTasks(for status: TaskStatus) -> [TaskItem] {
        tasks
            .filter { $0.status == status }
            .sorted { lhs, rhs in
                if lhs.priority.sortRank != rhs.priority.sortRank {
                    return lhs.priority.sortRank > rhs.priority.sortRank
                }
                switch (lhs.manualOrder, rhs.manualOrder) {
                case let (.some(lhsOrder), .some(rhsOrder)) where lhsOrder != rhsOrder:
                    return lhsOrder > rhsOrder
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    break
                }
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    /// Memoized per revision: SwiftUI evaluates view bodies far more often
    /// than tasks change, so repeated calls between edits are O(1). Every
    /// mutation path goes through save()/reloadTasks(), which bump `revision`.
    func snapshot(for scope: TaskScope) -> TaskScopeSnapshot {
        if let cached = snapshotCache[scope], cached.revision == revision {
            return cached.snapshot
        }

        let sections = scope.statuses.compactMap { status -> TaskSectionSnapshot? in
            let statusTasks = orderedTasks(for: status)
            guard !statusTasks.isEmpty else { return nil }
            return TaskSectionSnapshot(status: status, tasks: statusTasks)
        }
        let activeStatuses = Set(scope.countedStatuses)
        let snapshot = TaskScopeSnapshot(
            sections: sections,
            visibleCount: sections.reduce(0) { $0 + $1.tasks.count },
            activeCount: sections.reduce(0) { count, section in
                count + (activeStatuses.contains(section.status) ? section.tasks.count : 0)
            }
        )
        snapshotCache[scope] = (revision, snapshot)
        return snapshot
    }

    @discardableResult
    func startAfterExternalDrag(taskID: UUID) -> Bool {
        guard let task = tasks.first(where: { $0.id == taskID }) else { return false }
        switch task.status {
        case .todo, .backlog:
            return setStatus(.inProgress, for: task)
        case .inProgress:
            return true
        case .done:
            return false
        }
    }

    /// Drop onto another row: same section reorders, a different section
    /// adopts that section's status (placing the task near the target row
    /// when their priorities allow it).
    @discardableResult
    func drop(taskID: UUID, onto targetID: UUID) -> Bool {
        guard taskID != targetID,
              let task = tasks.first(where: { $0.id == taskID }),
              let target = tasks.first(where: { $0.id == targetID }) else {
            return false
        }

        if task.status == target.status {
            return reorder(taskID: taskID, relativeTo: targetID)
        }

        guard setStatus(target.status, for: task) else { return false }
        if task.priority == target.priority {
            reorder(taskID: taskID, relativeTo: targetID)
        }
        return true
    }

    /// Drop onto a section's own area (header, gaps, empty placeholder).
    @discardableResult
    func drop(taskID: UUID, into status: TaskStatus) -> Bool {
        guard let task = tasks.first(where: { $0.id == taskID }),
              task.status != status else {
            return false
        }
        return setStatus(status, for: task)
    }

    @discardableResult
    func reorder(taskID: UUID, relativeTo targetID: UUID) -> Bool {
        guard taskID != targetID,
              let task = tasks.first(where: { $0.id == taskID }),
              let target = tasks.first(where: { $0.id == targetID }),
              task.status == target.status,
              task.priority == target.priority else {
            return false
        }

        var group = orderedTasks(for: task.status).filter { $0.priority == task.priority }
        guard let sourceIndex = group.firstIndex(where: { $0.id == taskID }),
              let targetIndex = group.firstIndex(where: { $0.id == targetID }) else {
            return false
        }

        let movedTask = group.remove(at: sourceIndex)
        group.insert(movedTask, at: min(targetIndex, group.count))

        guard let destinationIndex = group.firstIndex(where: { $0.id == taskID }) else {
            return false
        }
        if let sparseOrder = sparseManualOrder(at: destinationIndex, in: group) {
            movedTask.manualOrder = sparseOrder
        } else {
            // Legacy stores can have missing or tightly packed values. Pay the
            // O(n) rebalance once, then normal reorders only dirty the moved row.
            assignSpacedManualOrders(to: group)
        }
        let timestamp = now()
        for replica in storedTasks(matching: task.id, fallback: task) {
            replica.manualOrder = movedTask.manualOrder
            replica.updatedAt = timestamp
        }
        return save()
    }

    func refresh() {
        do {
            try reloadTasks()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try persist(context)
            lastErrorMessage = nil
            revision &+= 1
            beginProtectedCloudSyncActivity(for: .exportData)
            return true
        } catch {
            let saveError = error.localizedDescription
            context.rollback()
            do {
                try reloadTasks()
                lastErrorMessage = saveError
            } catch {
                lastErrorMessage = "\(saveError) · Reload failed: \(error.localizedDescription)"
            }
            return false
        }
    }

    private func reloadTasks() throws {
        // A long-lived ModelContext can return cached model instances after
        // CloudKit updates the underlying store. Refresh through a new context
        // so remote values replace the old objects instead of being written
        // back to CloudKit by the next local save.
        let refreshedContext = ModelContext(container)
        let fetched = try refreshedContext.fetch(FetchDescriptor<TaskItem>())
        context = refreshedContext
        tasks = visibleUniqueTasks(from: fetched)
        revision &+= 1
    }

    /// CloudKit can't enforce a unique UUID attribute. If a malformed import
    /// ever produces duplicates, expose one app-level record. Never delete
    /// duplicates during refresh: device clocks aren't an ownership signal,
    /// and a cleanup save could destroy the valid peer copy across CloudKit.
    private func visibleUniqueTasks(from fetched: [TaskItem]) -> [TaskItem] {
        var newestByID: [UUID: TaskItem] = [:]

        for task in fetched {
            guard let existing = newestByID[task.id] else {
                newestByID[task.id] = task
                continue
            }

            if task.updatedAt > existing.updatedAt {
                newestByID[task.id] = task
            } else if task.updatedAt == existing.updatedAt,
                      Self.tieBreakKey(for: task) > Self.tieBreakKey(for: existing) {
                newestByID[task.id] = task
            }
        }

        return fetched.filter { task in
            newestByID[task.id] === task
        }
    }

    private func storedTasks(matching id: UUID, fallback: TaskItem) -> [TaskItem] {
        guard let stored = try? context.fetch(FetchDescriptor<TaskItem>()) else {
            return [fallback]
        }
        let matches = stored.filter { $0.id == id }
        return matches.isEmpty ? [fallback] : matches
    }

    private func observeRemoteChanges() {
        remoteChangeObservation = NotificationCenter.default.publisher(
            for: .NSPersistentStoreRemoteChange
        )
        .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.refresh()
        }
    }

    private func observeCloudKitEvents() {
        cloudKitEventObservation = NotificationCenter.default.publisher(
            for: NSPersistentCloudKitContainer.eventChangedNotification
        )
        .compactMap { notification in
            notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
        }
        .receive(on: DispatchQueue.main)
        .sink { [weak self] event in
            guard let self, let kind = Self.activityKind(for: event.type) else { return }
            handleCloudSyncEvent(CloudSyncEventUpdate(
                id: event.identifier,
                kind: kind,
                endedAt: event.endDate,
                succeeded: event.succeeded,
                errorMessage: Self.cloudSyncErrorMessage(event.error)
            ))
        }
    }

    /// A successful CloudKit import means the SQLite store has changed, but
    /// macOS does not reliably emit `NSPersistentStoreRemoteChange` for every
    /// SwiftData import. Coalesce completed imports and replace the context so
    /// the panel cannot remain attached to stale model instances.
    func handleCloudSyncEvent(_ update: CloudSyncEventUpdate) {
        if update.endedAt == nil {
            beginProtectedCloudSyncActivity(for: update.kind)
        } else if update.kind == .exportData {
            endProtectedCloudSyncActivity(for: .exportData)
        }

        cloudSyncStatus.apply(update)
        if !update.succeeded, let errorMessage = update.errorMessage {
            NSLog("CloudKit %@ failed: %@", String(describing: update.kind), errorMessage)
        }
        // A failed import may still have committed earlier batches. Refresh
        // after every completed import so partially applied changes are not
        // left hidden behind stale SwiftData model instances.
        guard update.kind == .importData, update.endedAt != nil else { return }

        cloudImportRefreshTask?.cancel()
        cloudImportRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            self?.refresh()
            self?.endProtectedCloudSyncActivity(for: .importData)
            self?.cloudImportRefreshTask = nil
        }
    }

    /// Peekaboo is an LSUIElement app and is normally hidden. Keep the process
    /// out of App Nap only while Core Data is handing a local save to CloudKit
    /// or applying an import, then release the assertion immediately. The
    /// timeout is a safety net for framework events that never complete.
    private func beginProtectedCloudSyncActivity(for kind: CloudSyncActivityKind) {
#if os(macOS)
        guard kind != .setup else { return }

        let processInfo = ProcessInfo.processInfo
        let reason: String
        switch kind {
        case .exportData:
            reason = "Exporting Peekaboo changes to iCloud"
            if exportActivityToken == nil {
                exportActivityToken = processInfo.beginActivity(
                    options: .userInitiatedAllowingIdleSystemSleep,
                    reason: reason
                )
            }
            exportActivityTimeoutTask?.cancel()
            exportActivityTimeoutTask = activityTimeoutTask(for: .exportData)
        case .importData:
            reason = "Importing Peekaboo changes from iCloud"
            if importActivityToken == nil {
                importActivityToken = processInfo.beginActivity(
                    options: .userInitiatedAllowingIdleSystemSleep,
                    reason: reason
                )
            }
            importActivityTimeoutTask?.cancel()
            importActivityTimeoutTask = activityTimeoutTask(for: .importData)
        case .setup:
            break
        }
#endif
    }

    private func endProtectedCloudSyncActivity(for kind: CloudSyncActivityKind) {
#if os(macOS)
        switch kind {
        case .exportData:
            exportActivityTimeoutTask?.cancel()
            exportActivityTimeoutTask = nil
            if let exportActivityToken {
                ProcessInfo.processInfo.endActivity(exportActivityToken)
                self.exportActivityToken = nil
            }
        case .importData:
            importActivityTimeoutTask?.cancel()
            importActivityTimeoutTask = nil
            if let importActivityToken {
                ProcessInfo.processInfo.endActivity(importActivityToken)
                self.importActivityToken = nil
            }
        case .setup:
            break
        }
#endif
    }

#if os(macOS)
    private func activityTimeoutTask(
        for kind: CloudSyncActivityKind
    ) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.cloudSyncActivityTimeout)
            guard !Task.isCancelled else { return }
            self?.endProtectedCloudSyncActivity(for: kind)
        }
    }
#endif

    private func nextManualOrder(
        status: TaskStatus,
        priority: TaskPriority,
        excluding excludedID: UUID? = nil
    ) -> Int64? {
        let group = tasks.filter {
            $0.id != excludedID && $0.status == status && $0.priority == priority
        }
        guard let maximum = group.compactMap(\.manualOrder).max() else { return nil }
        guard maximum <= .max - Self.manualOrderStride else {
            let orderedGroup = orderedTasks(for: status).filter {
                $0.id != excludedID && $0.priority == priority
            }
            assignSpacedManualOrders(to: orderedGroup)
            return Int64(orderedGroup.count + 1) * Self.manualOrderStride
        }
        return maximum + Self.manualOrderStride
    }

    private func sparseManualOrder(at index: Int, in orderedGroup: [TaskItem]) -> Int64? {
        guard orderedGroup.indices.contains(index) else { return nil }
        if orderedGroup.count == 1 { return Self.manualOrderStride }

        if index == 0 {
            guard let lower = orderedGroup[1].manualOrder,
                  lower <= .max - Self.manualOrderStride else { return nil }
            return lower + Self.manualOrderStride
        }

        if index == orderedGroup.count - 1 {
            guard let upper = orderedGroup[index - 1].manualOrder,
                  upper >= .min + Self.manualOrderStride else { return nil }
            return upper - Self.manualOrderStride
        }

        guard let upper = orderedGroup[index - 1].manualOrder,
              let lower = orderedGroup[index + 1].manualOrder,
              upper > lower else { return nil }
        let (distance, overflowed) = upper.subtractingReportingOverflow(lower)
        guard !overflowed, distance > 1 else { return nil }
        return lower + (distance / 2)
    }

    private func assignSpacedManualOrders(to orderedGroup: [TaskItem]) {
        for (index, item) in orderedGroup.enumerated() {
            item.manualOrder = Int64(orderedGroup.count - index) * Self.manualOrderStride
        }
    }

    private static func activityKind(
        for type: NSPersistentCloudKitContainer.EventType
    ) -> CloudSyncActivityKind? {
        switch type {
        case .setup: .setup
        case .import: .importData
        case .export: .exportData
        @unknown default: nil
        }
    }

    private static func cloudSyncErrorMessage(_ error: Error?) -> String? {
        guard let error else { return nil }
        let nsError = error as NSError
        var message = "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            message += " · \(underlyingError.domain) \(underlyingError.code): "
                + underlyingError.localizedDescription
        }
        return message
    }

    private static func normalized(_ title: String) -> String {
        title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func tieBreakKey(for task: TaskItem) -> String {
        [
            task.title,
            task.statusRaw,
            task.priorityRaw,
            String(task.createdAt.timeIntervalSinceReferenceDate.bitPattern),
            task.completedAt.map { String($0.timeIntervalSinceReferenceDate.bitPattern) } ?? "",
            task.manualOrder.map(String.init) ?? "",
            String(reflecting: task.persistentModelID)
        ].joined(separator: "\u{1F}")
    }
}
