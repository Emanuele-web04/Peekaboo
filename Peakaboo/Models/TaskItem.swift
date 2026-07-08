import Foundation
import SwiftData

@Model
final class TaskItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var statusRaw: String
    var priorityRaw: String
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        status: TaskStatus = .todo,
        priority: TaskPriority = .medium,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        statusRaw = status.rawValue
        priorityRaw = priority.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.completedAt = completedAt
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .todo }
        set { statusRaw = newValue.rawValue }
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }
}
