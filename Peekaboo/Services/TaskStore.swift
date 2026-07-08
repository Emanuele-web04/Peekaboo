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
            createdAt: timestamp
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
        task.priority = priority
        task.updatedAt = now()
        save()
    }

    func setStatus(_ status: TaskStatus, for task: TaskItem) {
        guard task.status != status else { return }
        objectWillChange.send()
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
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func refresh() {
        do {
            tasks = try context.fetch(FetchDescriptor<TaskItem>())
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            try context.save()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            context.rollback()
            refresh()
        }
    }

    private static func normalized(_ title: String) -> String {
        title
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
