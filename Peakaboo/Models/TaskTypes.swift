import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo
    case inProgress
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "To do"
        case .inProgress: "In Progress"
        case .done: "Done"
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
