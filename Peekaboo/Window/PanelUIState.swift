import Combine
import Foundation

@MainActor
final class PanelUIState: ObservableObject {
    @Published var isComposerPresented = false
    @Published var editingTaskID: UUID?
    @Published var isMenuTracking = false
    @Published private(set) var selectedScope: TaskScope = .tasks
    private(set) var draggedTaskID: UUID?

    var isInteractionLocked: Bool {
        isComposerPresented || editingTaskID != nil || isMenuTracking
    }

    func beginAdding() {
        editingTaskID = nil
        isComposerPresented = true
    }

    func selectScope(_ scope: TaskScope) {
        guard selectedScope != scope else { return }
        isComposerPresented = false
        editingTaskID = nil
        draggedTaskID = nil
        selectedScope = scope
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

    func beginDragging(_ task: TaskItem) {
        draggedTaskID = task.id
    }

    func endDragging() {
        draggedTaskID = nil
    }

    func finishDragging(releasedOutsidePanel: Bool) -> UUID? {
        guard let draggedTaskID else { return nil }
        self.draggedTaskID = nil
        return releasedOutsidePanel ? draggedTaskID : nil
    }
}
