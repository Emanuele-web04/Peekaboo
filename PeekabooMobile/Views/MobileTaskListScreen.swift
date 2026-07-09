import SwiftUI

struct MobileTaskListScreen: View {
    @ObservedObject var store: TaskStore
    let iCloudAvailability: ICloudAvailability
    let refresh: () async -> Void

    @State private var selectedScope: TaskScope = .tasks
    @State private var editor: MobileTaskEditorConfiguration?

    var body: some View {
        let snapshot = store.snapshot(for: selectedScope)

        NavigationStack {
            List {
                overview(snapshot: snapshot)

                if snapshot.visibleCount == 0 {
                    emptyState
                } else {
                    ForEach(snapshot.sections) { section in
                        Section {
                            ForEach(section.tasks) { task in
                                MobileTaskRow(
                                    store: store,
                                    task: task,
                                    edit: { editor = .edit(task) }
                                )
                            }
                        } header: {
                            Text("\(section.status.title) · \(section.tasks.count)")
                        }
                    }
                }

                syncStatus

                if let message = store.lastErrorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Peekaboo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editor = .create(selectedScope.creationStatus)
                    } label: {
                        Label(newItemTitle, systemImage: "plus")
                    }
                    .accessibilityIdentifier("add-task-button")
                }
            }
            .refreshable { await refresh() }
            .sheet(item: $editor) { configuration in
                MobileTaskEditor(store: store, configuration: configuration)
            }
        }
    }

    private func overview(snapshot: TaskScopeSnapshot) -> some View {
        Section {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedScope == .tasks ? "Tasks" : "Ideas for later")
                        .font(.headline)
                    Text(activeSubtitle(count: snapshot.activeCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(snapshot.activeCount)")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .contentTransition(.numericText())
            }
            .padding(.vertical, 4)

            Picker("Scope", selection: $selectedScope) {
                ForEach(TaskScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("task-scope-picker")
        }
    }

    private var emptyState: some View {
        Section {
            ContentUnavailableView {
                Label(
                    selectedScope == .tasks ? "Nothing hiding here" : "No ideas waiting",
                    systemImage: selectedScope == .tasks ? "checkmark.circle" : "lightbulb"
                )
            } description: {
                Text(
                    selectedScope == .tasks
                        ? "Add a task and it will appear on your Mac too."
                        : "Capture an idea now and promote it when you're ready."
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    private var syncStatus: some View {
        Section("Sync") {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: syncSymbol)
                    .foregroundStyle(syncTint)
                    .font(.title3)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(iCloudAvailability.title)
                        .font(.subheadline.weight(.medium))
                    Text(iCloudAvailability.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var syncSymbol: String {
        switch iCloudAvailability {
        case .available: "checkmark.icloud.fill"
        case .checking: "icloud"
        case .noAccount, .restricted, .temporarilyUnavailable, .unavailable:
            "exclamationmark.icloud"
        }
    }

    private var syncTint: Color {
        iCloudAvailability == .available ? .accentColor : .secondary
    }

    private func activeSubtitle(count: Int) -> String {
        switch selectedScope {
        case .tasks: count == 1 ? "1 active task" : "\(count) active tasks"
        case .backlog: count == 1 ? "1 idea" : "\(count) ideas"
        }
    }

    private var newItemTitle: String {
        selectedScope == .tasks ? "New Task" : "New Backlog Idea"
    }
}
