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
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What needs doing?", text: $title, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($titleIsFocused)
                        .accessibilityIdentifier("task-title-field")
                }

                Section("Details") {
                    Picker("Status", selection: $status) {
                        ForEach(TaskStatus.moveMenuOrder) { status in
                            Text(status.title).tag(status)
                        }
                    }

                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases.reversed()) { priority in
                            Text(priority.title).tag(priority)
                        }
                    }
                }

                if let message = store.lastErrorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(editorTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(normalizedTitle.isEmpty)
                }
            }
            .onAppear { titleIsFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private var editorTitle: String {
        switch configuration.mode {
        case .create: "New Task"
        case .edit: "Edit Task"
        }
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        let succeeded: Bool
        switch configuration.mode {
        case .create:
            succeeded = store.create(
                title: title,
                priority: priority,
                status: status
            ) != nil
        case let .edit(task):
            succeeded = store.update(
                task,
                title: title,
                priority: priority,
                status: status
            )
        }

        if succeeded { dismiss() }
    }
}
