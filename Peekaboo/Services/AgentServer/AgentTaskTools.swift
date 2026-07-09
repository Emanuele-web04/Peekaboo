import Foundation

enum AgentToolError: Error {
    case unknownTool(String)
    case invalidArguments(String)
    case notFound(String)
    case storeFailure(String)

    var message: String {
        switch self {
        case let .unknownTool(name): "Unknown tool: \(name)"
        case let .invalidArguments(details): details
        case let .notFound(id): "No task exists with id \(id)."
        case let .storeFailure(details): "The change could not be saved: \(details)"
        }
    }
}

/// Executes MCP tool calls against the app's task store so agent edits follow
/// the same rules (ordering, timestamps, cleanup) as edits made in the UI.
@MainActor
final class AgentTaskTools {
    private let store: TaskStore

    init(store: TaskStore) {
        self.store = store
    }

    static let definitions: [[String: Any]] = [
        [
            "name": "list_tasks",
            "description": "List Peekaboo tasks in the order the app displays them. Optionally filter by status. Statuses: inProgress, todo, done, backlog.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "status": [
                        "type": "string",
                        "enum": TaskStatus.allCases.map(\.rawValue),
                        "description": "Only return tasks with this status."
                    ]
                ],
                "additionalProperties": false
            ]
        ],
        [
            "name": "create_task",
            "description": "Create a task in Peekaboo. Use status backlog for ideas that are not ready to work on.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "title": [
                        "type": "string",
                        "description": "Short task title. Whitespace is collapsed."
                    ],
                    "status": [
                        "type": "string",
                        "enum": ["todo", "inProgress", "backlog"],
                        "description": "Initial status. Defaults to todo."
                    ],
                    "priority": [
                        "type": "string",
                        "enum": TaskPriority.allCases.map(\.rawValue),
                        "description": "Priority. Defaults to none."
                    ]
                ],
                "required": ["title"],
                "additionalProperties": false
            ]
        ],
        [
            "name": "update_task",
            "description": "Update a task's title, status, or priority. Set status to done to complete a task, or back to todo to reopen it.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": [
                        "type": "string",
                        "description": "Task id returned by list_tasks or create_task."
                    ],
                    "title": ["type": "string"],
                    "status": [
                        "type": "string",
                        "enum": TaskStatus.allCases.map(\.rawValue)
                    ],
                    "priority": [
                        "type": "string",
                        "enum": TaskPriority.allCases.map(\.rawValue)
                    ]
                ],
                "required": ["id"],
                "additionalProperties": false
            ]
        ],
        [
            "name": "delete_task",
            "description": "Delete a task permanently. Prefer update_task with status done for finished work.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "id": [
                        "type": "string",
                        "description": "Task id returned by list_tasks or create_task."
                    ]
                ],
                "required": ["id"],
                "additionalProperties": false
            ]
        ]
    ]

    func call(name: String, arguments: [String: Any]) throws -> String {
        switch name {
        case "list_tasks": try listTasks(arguments)
        case "create_task": try createTask(arguments)
        case "update_task": try updateTask(arguments)
        case "delete_task": try deleteTask(arguments)
        default: throw AgentToolError.unknownTool(name)
        }
    }

    private func listTasks(_ arguments: [String: Any]) throws -> String {
        let statuses: [TaskStatus]
        if arguments["status"] != nil {
            statuses = [try status(from: arguments, allowed: TaskStatus.allCases)]
        } else {
            statuses = [.inProgress, .todo, .done, .backlog]
        }
        let tasks = statuses.flatMap(store.orderedTasks(for:))
        return try encode(["count": tasks.count, "tasks": tasks.map(serialize)])
    }

    private func createTask(_ arguments: [String: Any]) throws -> String {
        guard let title = arguments["title"] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentToolError.invalidArguments("A non-empty title is required.")
        }
        let status = arguments["status"] == nil
            ? .todo
            : try status(from: arguments, allowed: [.todo, .inProgress, .backlog])
        let priority = try priority(from: arguments)
        guard let task = store.create(title: title, priority: priority, status: status) else {
            throw AgentToolError.storeFailure(store.lastErrorMessage ?? "Unknown error.")
        }
        return try encode(["task": serialize(task)])
    }

    private func updateTask(_ arguments: [String: Any]) throws -> String {
        // Validate every argument before mutating so an invalid one
        // doesn't leave the task half-updated.
        let task = try findTask(arguments)
        var newTitle: String?
        if let rawTitle = arguments["title"] {
            guard let title = rawTitle as? String,
                  !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AgentToolError.invalidArguments("The title must be a non-empty string.")
            }
            newTitle = title
        }
        let newPriority = arguments["priority"] == nil ? nil : try priority(from: arguments)
        let newStatus = arguments["status"] == nil
            ? nil
            : try status(from: arguments, allowed: TaskStatus.allCases)

        if let newTitle {
            try perform { store.rename(task, to: newTitle) }
        }
        if let newPriority {
            try perform { store.setPriority(newPriority, for: task) }
        }
        if let newStatus {
            try perform { store.setStatus(newStatus, for: task) }
        }
        return try encode(["task": serialize(task)])
    }

    private func deleteTask(_ arguments: [String: Any]) throws -> String {
        let task = try findTask(arguments)
        let id = task.id.uuidString
        try perform { store.delete(task) }
        return try encode(["deleted": id])
    }

    private func findTask(_ arguments: [String: Any]) throws -> TaskItem {
        guard let rawID = arguments["id"] as? String, let id = UUID(uuidString: rawID) else {
            throw AgentToolError.invalidArguments("A task id (UUID) is required.")
        }
        guard let task = store.tasks.first(where: { $0.id == id }) else {
            throw AgentToolError.notFound(rawID)
        }
        return task
    }

    private func status(from arguments: [String: Any], allowed: [TaskStatus]) throws -> TaskStatus {
        guard let raw = arguments["status"] as? String,
              let status = TaskStatus(rawValue: raw),
              allowed.contains(status) else {
            let options = allowed.map(\.rawValue).joined(separator: ", ")
            throw AgentToolError.invalidArguments("Invalid status. Use one of: \(options).")
        }
        return status
    }

    private func priority(from arguments: [String: Any]) throws -> TaskPriority {
        guard let raw = arguments["priority"] else { return .none }
        guard let rawString = raw as? String, let priority = TaskPriority(rawValue: rawString) else {
            let options = TaskPriority.allCases.map(\.rawValue).joined(separator: ", ")
            throw AgentToolError.invalidArguments("Invalid priority. Use one of: \(options).")
        }
        return priority
    }

    private func perform(_ change: () throws -> Bool) throws {
        guard try change() else {
            throw AgentToolError.storeFailure(store.lastErrorMessage ?? "Unknown error.")
        }
    }

    private func serialize(_ task: TaskItem) -> [String: Any] {
        var payload: [String: Any] = [
            "id": task.id.uuidString,
            "title": task.title,
            "status": task.status.rawValue,
            "priority": task.priority.rawValue,
            "createdAt": Self.dateFormatter.string(from: task.createdAt),
            "updatedAt": Self.dateFormatter.string(from: task.updatedAt)
        ]
        if let completedAt = task.completedAt {
            payload["completedAt"] = Self.dateFormatter.string(from: completedAt)
        }
        return payload
    }

    private func encode(_ payload: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static let dateFormatter = ISO8601DateFormatter()
}
