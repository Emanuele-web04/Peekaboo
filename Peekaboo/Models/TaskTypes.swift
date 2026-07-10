import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo
    case inProgress
    case done
    case backlog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "To do"
        case .inProgress: "In Progress"
        case .done: "Done"
        case .backlog: "Backlog"
        }
    }

    var primaryActionDestination: TaskStatus {
        switch self {
        case .backlog, .done: .todo
        case .todo, .inProgress: .done
        }
    }

    var doubleClickDestination: TaskStatus? {
        switch self {
        case .backlog: .todo
        case .todo: .inProgress
        case .inProgress: .todo
        case .done: nil
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .backlog: "Move to To do"
        case .todo, .inProgress: "Mark done"
        case .done: "Move back to To do"
        }
    }

    var doubleClickTitle: String {
        switch self {
        case .backlog: "Double-click to move to To do"
        case .todo: "Double-click to start"
        case .inProgress: "Double-click to move back to To do"
        case .done: title
        }
    }

    static let moveMenuOrder: [TaskStatus] = [.backlog, .inProgress, .todo, .done]
}

enum TaskScope: String, CaseIterable, Identifiable {
    case tasks
    case backlog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: "Tasks"
        case .backlog: "Backlog"
        }
    }

    var statuses: [TaskStatus] {
        switch self {
        case .tasks: [.inProgress, .todo, .done]
        case .backlog: [.backlog]
        }
    }

    var countedStatuses: [TaskStatus] {
        switch self {
        case .tasks: [.inProgress, .todo]
        case .backlog: [.backlog]
        }
    }

    var creationStatus: TaskStatus {
        switch self {
        case .tasks: .todo
        case .backlog: .backlog
        }
    }

    var newItemTitle: String {
        switch self {
        case .tasks: "New Task"
        case .backlog: "New Backlog Idea"
        }
    }

    var composerPlaceholder: String {
        switch self {
        case .tasks: "What needs doing?"
        case .backlog: "Capture an idea…"
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .tasks: "Nothing hiding here"
        case .backlog: "No ideas waiting"
        }
    }

    func activeSubtitle(count: Int) -> String {
        switch self {
        case .tasks: count == 1 ? "1 Active Task" : "\(count) Active Tasks"
        case .backlog: count == 1 ? "1 Idea" : "\(count) Ideas"
        }
    }
}

enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case none
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var sortRank: Int {
        switch self {
        case .none: -1
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }
}

enum ScreenCorner: String, Codable, CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}
