import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TaskRowView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var uiState: PanelUIState
    let task: TaskItem

    @State private var editTitle = ""
    @State private var isHovering = false
    @FocusState private var isRenameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isEditing: Bool { uiState.editingTaskID == task.id }

    var body: some View {
        HStack(spacing: 8) {
            TaskStatusButton(status: task.status, priority: task.priority) {
                store.performPrimaryAction(task)
            }
            .accessibilityIdentifier("complete-task-\(task.id.uuidString)")

            Group {
                if isEditing {
                    TextField("Task title", text: $editTitle, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .focused($isRenameFocused)
                        .onSubmit(commitRename)
                        .onExitCommand(perform: cancelRename)
                        .accessibilityIdentifier("edit-task-title-\(task.id.uuidString)")
                } else {
                    Text(task.title)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                        .strikethrough(task.status == .done, color: .secondary)
                        .foregroundStyle(task.status == .done ? .secondary : .primary)
                        .accessibilityLabel(task.title)
                }
            }
            .font(.system(size: 13, weight: task.status == .inProgress ? .medium : .regular, design: .rounded))
            .frame(maxWidth: .infinity, alignment: .leading)

            trailingAction
        }
        .padding(.vertical, 2)
        .frame(minHeight: PeekabooStyle.rowHeight)
        .padding(.horizontal, 4)
        .background(
            Color.primary.opacity(isHovering ? 0.055 : 0),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: handleDoubleClick)
        .help(progressToggleHelp)
        .contextMenu { taskActions }
        .onDrag {
            dragItemProvider()
        } preview: {
            dragPreview
        }
        .onDrop(of: [.utf8PlainText], isTargeted: nil) { providers, _ in
            acceptDrop(from: providers)
        }
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : PeekabooMotion.quick) {
                isHovering = hovering
            }
        }
        .animation(reduceMotion ? nil : PeekabooMotion.spring, value: task.statusRaw)
        .animation(reduceMotion ? nil : PeekabooMotion.quick, value: task.priorityRaw)
        .onChange(of: isEditing) { _, nowEditing in
            guard nowEditing else { return }
            editTitle = task.title
            DispatchQueue.main.async { isRenameFocused = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-row-\(task.id.uuidString)")
    }

    private var dragPreview: some View {
        HStack(spacing: 7) {
            TaskStatusMark(status: task.status, priority: task.priority, size: 13)
            Text(task.title)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func dragItemProvider() -> NSItemProvider {
        uiState.beginDragging(task)
        return TaskDragPayload(title: task.title).itemProvider()
    }

    private func acceptDrop(from providers: [NSItemProvider]) -> Bool {
        guard providers.contains(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier)
        }), let draggedTaskID = uiState.draggedTaskID else {
            return false
        }

        uiState.endDragging()
        return store.reorder(taskID: draggedTaskID, relativeTo: task.id)
    }

    @ViewBuilder
    private var trailingAction: some View {
        if isEditing {
            Button(action: commitRename) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Save title")
            .accessibilityLabel("Save title")
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        } else {
            Menu {
                taskActions
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(isHovering ? 1 : 0.38)
            .help("Edit task")
            .accessibilityLabel("Edit task")
            .accessibilityIdentifier("task-actions-\(task.id.uuidString)")
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var taskActions: some View {
        Button("Edit title…", systemImage: "pencil") {
            uiState.beginEditing(task)
        }

        Button("Copy", systemImage: "doc.on.doc") {
            copyTitle()
        }

        Menu("Priority") {
            ForEach(TaskPriority.allCases.reversed()) { priority in
                Button {
                    store.setPriority(priority, for: task)
                } label: {
                    if task.priority == priority {
                        Label(priority.title, systemImage: "checkmark")
                    } else {
                        Text(priority.title)
                    }
                }
            }
        }

        Menu("Move to") {
            ForEach(TaskStatus.moveMenuOrder) { status in
                Button {
                    store.setStatus(status, for: task)
                } label: {
                    if task.status == status {
                        Label(status.title, systemImage: "checkmark")
                    } else {
                        Text(status.title)
                    }
                }
            }
        }

        Divider()

        Button("Delete", systemImage: "trash", role: .destructive) {
            store.delete(task)
        }
    }

    private func commitRename() {
        if store.rename(task, to: editTitle) {
            uiState.endEditing()
        }
    }

    private func cancelRename() {
        uiState.endEditing()
    }

    private func handleDoubleClick() {
        guard !isEditing else { return }
        store.performDoubleClickAction(task)
    }

    private func copyTitle() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(task.title, forType: .string)
    }

    private var progressToggleHelp: String {
        task.status.doubleClickTitle
    }
}
