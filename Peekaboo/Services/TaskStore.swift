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

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var revision: UInt64 = 0

    private let context: ModelContext
    private let now: () -> Date
    private let persist: (ModelContext) throws -> Void
    private var remoteChangeObservation: AnyCancellable?

    init(
        container: ModelContainer,
        now: @escaping () -> Date = Date.init,
        persist: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        context = ModelContext(container)
        self.now = now
        self.persist = persist
        refresh()
        observeRemoteChanges()
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
        let normalizedTitle = title.map(Self.normalized)
        if let normalizedTitle, normalizedTitle.isEmpty { return false }

        let destinationPriority = priority ?? task.priority
        let destinationStatus = status ?? task.status
        let titleChanged = normalizedTitle.map { $0 != task.title } ?? false
        let priorityChanged = destinationPriority != task.priority
        let statusChanged = destinationStatus != task.status
        guard titleChanged || priorityChanged || statusChanged else { return true }

        let timestamp = now()
        if priorityChanged || statusChanged {
            task.manualOrder = nextManualOrder(
                status: destinationStatus,
                priority: destinationPriority,
                excluding: task.id
            )
        }
        if let normalizedTitle {
            task.title = normalizedTitle
        }
        task.priority = destinationPriority
        task.status = destinationStatus
        task.updatedAt = timestamp
        if statusChanged {
            task.completedAt = destinationStatus == .done ? timestamp : nil
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
        context.delete(task)
        tasks.removeAll { $0.id == task.id }
        return save()
    }

    @discardableResult
    func purgeCompleted(before cutoff: Date) -> Int {
        let expired = tasks.filter { task in
            task.status == .done && (task.completedAt.map { $0 < cutoff } ?? false)
        }
        guard !expired.isEmpty else { return 0 }
        let expiredIDs = Set(expired.map(\.id))
        expired.forEach(context.delete)
        tasks.removeAll { expiredIDs.contains($0.id) }
        return save() ? expired.count : 0
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

    func snapshot(for scope: TaskScope) -> TaskScopeSnapshot {
        let sections = scope.statuses.compactMap { status -> TaskSectionSnapshot? in
            let statusTasks = orderedTasks(for: status)
            guard !statusTasks.isEmpty else { return nil }
            return TaskSectionSnapshot(status: status, tasks: statusTasks)
        }
        let activeStatuses = Set(scope.countedStatuses)
        return TaskScopeSnapshot(
            sections: sections,
            visibleCount: sections.reduce(0) { $0 + $1.tasks.count },
            activeCount: sections.reduce(0) { count, section in
                count + (activeStatuses.contains(section.status) ? section.tasks.count : 0)
            }
        )
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

        for (index, item) in group.enumerated() {
            item.manualOrder = Int64(group.count - index)
        }
        task.updatedAt = now()
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
        let fetched = try context.fetch(FetchDescriptor<TaskItem>())
        tasks = try deduplicated(fetched)
        revision &+= 1
    }

    /// CloudKit can't enforce a unique UUID attribute. If a malformed import
    /// ever produces duplicates, retain the newest app-level record. Exact
    /// timestamp ties stay in the store: deleting an arbitrary physical copy
    /// on each device could sync two opposing deletions and lose both.
    private func deduplicated(_ fetched: [TaskItem]) throws -> [TaskItem] {
        var newestByID: [UUID: TaskItem] = [:]
        var strictlyOlderDuplicates: [TaskItem] = []

        for task in fetched {
            guard let existing = newestByID[task.id] else {
                newestByID[task.id] = task
                continue
            }

            if task.updatedAt > existing.updatedAt {
                newestByID[task.id] = task
                strictlyOlderDuplicates.append(existing)
            } else if task.updatedAt < existing.updatedAt {
                strictlyOlderDuplicates.append(task)
            } else if Self.tieBreakKey(for: task) > Self.tieBreakKey(for: existing) {
                // Select the same visible value on every device, but leave both
                // physical records intact until a real edit makes one newer.
                newestByID[task.id] = task
            }
        }

        if !strictlyOlderDuplicates.isEmpty {
            strictlyOlderDuplicates.forEach(context.delete)
            do {
                try persist(context)
            } catch {
                context.rollback()
                throw error
            }
        }

        return fetched.filter { task in
            newestByID[task.id] === task
        }
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

    private func nextManualOrder(
        status: TaskStatus,
        priority: TaskPriority,
        excluding excludedID: UUID? = nil
    ) -> Int64? {
        let group = tasks.filter {
            $0.id != excludedID && $0.status == status && $0.priority == priority
        }
        guard let maximum = group.compactMap(\.manualOrder).max() else { return nil }
        guard maximum == .max else { return maximum + 1 }

        let orderedGroup = orderedTasks(for: status).filter {
            $0.id != excludedID && $0.priority == priority
        }
        for (index, item) in orderedGroup.enumerated() {
            item.manualOrder = Int64(orderedGroup.count - index)
        }
        return Int64(orderedGroup.count + 1)
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
            task.manualOrder.map(String.init) ?? ""
        ].joined(separator: "\u{1F}")
    }
}
