import SwiftUI
import UIKit

struct MobileTaskRow: View {
    @ObservedObject var store: TaskStore
    let task: TaskItem
    let edit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                store.performPrimaryAction(task)
            } label: {
                Image(systemName: task.status.mobileSymbol)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(task.priority.mobileTint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.status.primaryActionTitle)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .foregroundStyle(task.status == .done ? .secondary : .primary)
                    .strikethrough(task.status == .done, color: .secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if task.priority != .none {
                    Text("\(task.priority.title) priority")
                        .font(.caption)
                        .foregroundStyle(task.priority.mobileTint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: edit)
        }
        .padding(.vertical, 3)
        .accessibilityIdentifier("task-row-\(task.id.uuidString)")
        .accessibilityAction(named: "Edit", edit)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                store.performPrimaryAction(task)
            } label: {
                Label(task.status.primaryActionTitle, systemImage: task.status.mobileActionSymbol)
            }
            .tint(task.status == .done ? .blue : .green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                store.delete(task)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button(action: edit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil", action: edit)
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = task.title
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
    }
}

private extension TaskStatus {
    var mobileSymbol: String {
        switch self {
        case .todo, .backlog: "circle"
        case .inProgress: "circle.inset.filled"
        case .done: "checkmark.circle.fill"
        }
    }

    var mobileActionSymbol: String {
        switch primaryActionDestination {
        case .done: "checkmark"
        case .todo: "arrow.uturn.backward"
        case .inProgress: "play"
        case .backlog: "tray"
        }
    }
}

private extension TaskPriority {
    var mobileTint: Color {
        switch self {
        case .none: .secondary
        case .low: .blue
        case .medium: .orange
        case .high: .red
        }
    }
}
