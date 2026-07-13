// Compact iPhone task row with the same internal actions as the macOS panel.
// Touch mapping: double-tap = double-click. Drag/reorder is owned by
// MobileTaskListScreen; a row context menu would steal its long press.
import SwiftUI
import UIKit

struct MobileTaskRow: View {
    @ObservedObject var store: TaskStore
    let task: TaskItem
    let isDragging: Bool
    let dragChanged: (CGPoint) -> Void
    let dragEnded: (CGPoint) -> Void
    let edit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var markScale: CGFloat = 1

    var body: some View {
        HStack(spacing: 12) {
            Button {
                animated { store.performPrimaryAction(task) }
            } label: {
                TaskStatusMark(status: task.status, priority: task.priority, size: 19)
                    .scaleEffect(markScale)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(reduceMotion ? nil : PeekabooMotion.spring, value: task.statusRaw)
            .accessibilityLabel(task.status.primaryActionTitle)
            .accessibilityValue("\(task.priority.title) priority")

            Text(task.title)
                .font(.system(size: 16, weight: task.status == .inProgress ? .medium : .regular, design: .rounded))
                .foregroundStyle(task.status == .done ? .secondary : .primary)
                .strikethrough(task.status == .done, color: .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(
                    TapGesture(count: 2)
                        .exclusively(before: TapGesture())
                        .onEnded { gesture in
                            switch gesture {
                            case .first:
                                animated { store.performDoubleClickAction(task) }
                            case .second:
                                edit()
                            }
                        }
                )

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
                .scaleEffect(isDragging ? 1.15 : 1)
                .highPriorityGesture(
                    DragGesture(
                        minimumDistance: 4,
                        coordinateSpace: .global
                    )
                    .onChanged { dragChanged($0.location) }
                    .onEnded { dragEnded($0.location) }
                )
                .accessibilityLabel("Drag \(task.title)")
                .accessibilityIdentifier("drag-task-\(task.id.uuidString)")
        }
        .padding(.vertical, 2)
        .animation(reduceMotion ? nil : PeekabooMotion.quick, value: task.priorityRaw)
        .animation(reduceMotion ? nil : PeekabooMotion.quick, value: task.statusRaw)
        // Gentle pulse on the status mark when the task enters In Progress.
        .onChange(of: task.statusRaw) { _, newValue in
            guard newValue == TaskStatus.inProgress.rawValue, !reduceMotion else { return }
            markScale = 1.3
            withAnimation(PeekabooMotion.spring) { markScale = 1 }
        }
        .accessibilityIdentifier("task-row-\(task.id.uuidString)")
        .accessibilityAction(named: "Edit", edit)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                animated { store.performPrimaryAction(task) }
            } label: {
                Label(task.status.primaryActionTitle, systemImage: primaryActionSymbol)
                    .labelStyle(.iconOnly)
            }
            .tint(task.status == .done ? .blue : .green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                animated { store.delete(task) }
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            Button(action: edit) {
                Label("Edit", systemImage: "pencil")
                    .labelStyle(.iconOnly)
            }
            .tint(.blue)
            Button {
                UIPasteboard.general.string = task.title
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .tint(.secondary)
        }
    }

    private var primaryActionSymbol: String {
        switch task.status.primaryActionDestination {
        case .done: "checkmark"
        case .todo: "arrow.uturn.backward"
        case .inProgress: "play"
        case .backlog: "tray"
        }
    }

    // List only animates row moves between sections when the data mutation
    // itself happens inside withAnimation, so every store call goes through here.
    private func animated(_ change: @escaping () -> Void) {
        withAnimation(reduceMotion ? nil : PeekabooMotion.spring, change)
    }
}
