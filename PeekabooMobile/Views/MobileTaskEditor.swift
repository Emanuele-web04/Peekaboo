import SwiftUI

struct MobileTaskEditorConfiguration: Identifiable {
    enum Mode {
        case create(TaskStatus)
        case edit(TaskItem)
    }

    let mode: Mode

    var id: String {
        switch mode {
        case let .create(status): "create-\(status.rawValue)"
        case let .edit(task): "edit-\(task.id.uuidString)"
        }
    }

    static func create(_ status: TaskStatus) -> Self {
        Self(mode: .create(status))
    }

    static func edit(_ task: TaskItem) -> Self {
        Self(mode: .edit(task))
    }
}

struct MobileTaskEditor: View {
    @ObservedObject var store: TaskStore
    let configuration: MobileTaskEditorConfiguration

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var priority: TaskPriority
    @State private var status: TaskStatus
    @FocusState private var titleIsFocused: Bool

    init(store: TaskStore, configuration: MobileTaskEditorConfiguration) {
        self.store = store
        self.configuration = configuration

        switch configuration.mode {
        case let .create(status):
            _title = State(initialValue: "")
            _priority = State(initialValue: .none)
            _status = State(initialValue: status)
        case let .edit(task):
            _title = State(initialValue: task.title)
            _priority = State(initialValue: task.priority)
            _status = State(initialValue: task.status)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            TextField(placeholder, text: $title, axis: .vertical)
                .font(.system(size: 17, design: .rounded))
                .lineLimit(1...5)
                .focused($titleIsFocused)
                .submitLabel(.done)
                .onSubmit(save)
                .accessibilityIdentifier("task-title-field")

            chipRow(label: "Priority") {
                ForEach(TaskPriority.allCases) { option in
                    priorityChip(option)
                }
            }

            chipRow(label: "Status") {
                ForEach(TaskStatus.moveMenuOrder) { option in
                    statusChip(option)
                }
            }

            if let message = store.lastErrorMessage {
                Text(message)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .fontDesign(.rounded)
        .presentationDetents([.height(300), .medium])
        .presentationDragIndicator(.visible)
        .animation(PeekabooMotion.quick, value: priority)
        .animation(PeekabooMotion.quick, value: status)
        .onAppear { titleIsFocused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(editorTitle)
                .font(.system(size: 17, weight: .semibold, design: .rounded))

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(0.06), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel")

            Button(action: save) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(
                        normalizedTitle.isEmpty ? Color.secondary.opacity(0.35) : Color.accentColor,
                        in: Circle()
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(normalizedTitle.isEmpty)
            .accessibilityLabel("Save")
            .accessibilityIdentifier("save-task")
        }
        .padding(.top, 6)
    }

    private func chipRow(label: String, @ViewBuilder chips: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(spacing: 7, content: chips)
            }
            .scrollIndicators(.never)
        }
    }

    private func priorityChip(_ option: TaskPriority) -> some View {
        let isSelected = priority == option

        return Button {
            priority = option
        } label: {
            HStack(spacing: 5) {
                Image(systemName: option == .none ? "flag" : "flag.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text(option.title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .foregroundStyle(option.color)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(option.color.opacity(isSelected ? 0.18 : 0.05), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(option.color.opacity(isSelected ? 0.38 : 0), lineWidth: 0.8)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.title) priority")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func statusChip(_ option: TaskStatus) -> some View {
        let isSelected = status == option

        return Button {
            status = option
        } label: {
            HStack(spacing: 6) {
                TaskStatusMark(status: option, priority: priority, size: 12)
                Text(option.title)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Color.primary.opacity(isSelected ? 0.1 : 0.04), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.primary.opacity(isSelected ? 0.16 : 0), lineWidth: 0.8)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var editorTitle: String {
        switch configuration.mode {
        case .create: "New Task"
        case .edit: "Edit Task"
        }
    }

    private var placeholder: String {
        status == .backlog ? "Capture an idea…" : "What needs doing?"
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        // Inside withAnimation so the list behind the sheet animates the
        // row moving to its new section/position instead of jumping.
        let succeeded = withAnimation(PeekabooMotion.spring) {
            switch configuration.mode {
            case .create:
                store.create(title: title, priority: priority, status: status) != nil
            case let .edit(task):
                store.update(task, title: title, priority: priority, status: status)
            }
        }

        if succeeded { dismiss() }
    }
}
