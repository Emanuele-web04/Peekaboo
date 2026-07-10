import AppKit
import Foundation
import UniformTypeIdentifiers

struct TaskDragPayload: Sendable {
    static let internalTaskType = UTType(
        exportedAs: "com.emanueledipietro.peekaboo.task-id"
    )

    let taskID: UUID?
    let title: String

    init(taskID: UUID? = nil, title: String) {
        self.taskID = taskID
        self.title = title
    }

    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        if let taskID {
            provider.registerDataRepresentation(
                forTypeIdentifier: Self.internalTaskType.identifier,
                visibility: .ownProcess
            ) { completion in
                completion(Data(taskID.uuidString.utf8), nil)
                return nil
            }
        }

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

    /// Resolve the task identity from the drag itself instead of transient UI
    /// state. The pointer monitor may clear that state as the mouse button is
    /// released, before SwiftUI finishes dispatching its drop callback.
    @discardableResult
    static func loadTaskID(
        from providers: [NSItemProvider],
        completion: @escaping @MainActor (UUID) -> Void
    ) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(internalTaskType.identifier)
        }) else { return false }

        provider.loadDataRepresentation(
            forTypeIdentifier: internalTaskType.identifier
        ) { data, _ in
            guard let data,
                  let rawValue = String(data: data, encoding: .utf8),
                  let taskID = UUID(uuidString: rawValue) else { return }
            Task { @MainActor in completion(taskID) }
        }
        return true
    }
}
