import Combine
import Foundation
import SwiftData

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var lastErrorMessage: String?

    private let context: ModelContext
    private let now: () -> Date

    init(container: ModelContainer, now: @escaping () -> Date = Date.init) {
        context = ModelContext(container)
        self.now = now
        refresh()
    }

    @discardableResult
    func create(title: String, priority: TaskPriority = .medium) -> TaskItem? {
        let normalizedTitle = Self.normalized(title)
        guard !normalizedTitle.isEmpty else { return nil }

        let timestamp = now()
        let task = TaskItem(
            title: normalizedTitle,
            status: .todo,
            priority: priority,
            createdAt: timestamp,
            manualOrder: nextManualOrder(status: .todo, priority: priority)
        )
        context.insert(task)
        tasks.append(task)
        save()
        return task
    }

    func rename(_ task: TaskItem, to title: String) {
        let normalizedTitle = Self.normalized(title)
        guard !normalizedTitle.isEmpty else { return }
        objectWillChange.send()
        task.title = normalizedTitle
        task.updatedAt = now()
        save()
    }

    func setPriority(_ priority: TaskPriority, for task: TaskItem) {
        guard task.priority != priority else { return }
        objectWillChange.send()
        task.manualOrder = nextManualOrder(status: task.status, priority: priority, excluding: task.id)
        task.priority = priority
        task.updatedAt = now()
        save()
    }

    func setStatus(_ status: TaskStatus, for task: TaskItem) {
        guard task.status != status else { return }
        objectWillChange.send()
        task.manualOrder = nextManualOrder(status: status, priority: task.priority, excluding: task.id)
        task.status = status
        task.updatedAt = now()
        task.completedAt = status == .done ? now() : nil
        save()
    }

    func advanceToInProgress(_ task: TaskItem) {
        guard task.status == .todo else { return }
        setStatus(.inProgress, for: task)
    }

    func toggleProgress(_ task: TaskItem) {
        switch task.status {
        case .todo:
            setStatus(.inProgress, for: task)
        case .inProgress:
            setStatus(.todo, for: task)
        case .done:
            break
        }
    }

    func markDone(_ task: TaskItem) {
        guard task.status != .done else { return }
        setStatus(.done, for: task)
    }

    func toggleCompletion(_ task: TaskItem) {
        setStatus(task.status == .done ? .todo : .done, for: task)
    }

    func delete(_ task: TaskItem) {
        context.delete(task)
        tasks.removeAll { $0.id == task.id }
        save()
    }

    @discardableResult
    func purgeCompleted(before cutoff: Date) -> Int {
        let expired = tasks.filter { task in
            task.status == .done && (task.completedAt.map { $0 < cutoff } ?? false)
        }
        expired.forEach(context.delete)
        tasks.removeAll { task in expired.contains { $0.id == task.id } }
        if !expired.isEmpty { save() }
        return expired.count
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

        objectWillChange.send()
        for (index, item) in group.enumerated() {
            item.manualOrder = Int64(group.count - index)
        }
        task.updatedAt = now()
        return save()
    }

    func refresh() {
        do {
            tasks = try context.fetch(FetchDescriptor<TaskItem>())
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try context.save()
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            context.rollback()
            refresh()
            return false
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
}
