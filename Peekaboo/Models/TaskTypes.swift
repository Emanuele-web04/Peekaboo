import AppKit
import Foundation
import UniformTypeIdentifiers

struct TaskDragPayload: Sendable {
    let id: UUID
    let title: String

    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        let plainTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.utf8PlainText.identifier,
            visibility: .all
        ) { completion in
            completion(Data(plainTitle.utf8), nil)
            return nil
        }
        return provider
    }
}

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
}

enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case none
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var shortLabel: String {
        switch self {
        case .none: "–"
        case .low: "L"
        case .medium: "M"
        case .high: "H"
        }
    }

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
