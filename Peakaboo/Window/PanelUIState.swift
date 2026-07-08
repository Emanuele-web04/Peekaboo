import Combine
import Foundation

@MainActor
final class PanelUIState: ObservableObject {
    @Published var isComposerPresented = false
    @Published var editingTaskID: UUID?
    @Published var isMenuTracking = false

    var isInteractionLocked: Bool {
        isComposerPresented || editingTaskID != nil || isMenuTracking
    }

    func beginAdding() {
        editingTaskID = nil
        isComposerPresented = true
    }

    func endAdding() {
        isComposerPresented = false
    }

    func beginEditing(_ task: TaskItem) {
        isComposerPresented = false
        editingTaskID = task.id
    }

    func endEditing() {
        editingTaskID = nil
    }
}
