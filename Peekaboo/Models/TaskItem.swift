import Foundation
import SwiftData

@Model
final class TaskItem {
    // CloudKit can't enforce SwiftData uniqueness. UUID generation plus the
    // TaskStore refresh deduplication keep the app-level identity stable.
    var id: UUID = UUID()
    var title: String = ""
    var statusRaw: String = TaskStatus.todo.rawValue
    var priorityRaw: String = TaskPriority.none.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var completedAt: Date? = nil
    var manualOrder: Int64? = nil

    init(
        id: UUID = UUID(),
        title: String,
        status: TaskStatus = .todo,
        priority: TaskPriority = .none,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        completedAt: Date? = nil,
        manualOrder: Int64? = nil
    ) {
        self.id = id
        self.title = title
        statusRaw = status.rawValue
        priorityRaw = priority.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.completedAt = completedAt
        self.manualOrder = manualOrder
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }
}
