import SwiftUI

struct MobileTaskListScreen: View {
    @ObservedObject var store: TaskStore
    let iCloudAvailability: ICloudAvailability
    let refresh: () async -> Void

    @State private var selectedScope: TaskScope = .tasks
    @State private var editor: MobileTaskEditorConfiguration?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let snapshot = store.snapshot(for: selectedScope)

        VStack(spacing: 0) {
            header(activeCount: snapshot.activeCount)
            scopePicker

            taskList(snapshot: snapshot)

            footer
        }
        .background(Color(uiColor: .systemBackground))
        .animation(reduceMotion ? nil : PeekabooMotion.spring, value: store.tasks.map(\.id))
        .animation(reduceMotion ? nil : PeekabooMotion.quick, value: selectedScope)
        .sheet(item: $editor) { configuration in
            MobileTaskEditor(store: store, configuration: configuration)
        }
    }

    // MARK: Header

    private func header(activeCount: Int) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Peekaboo")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(selectedScope.activeSubtitle(count: activeCount))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : PeekabooMotion.quick, value: activeCount)
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: Scope picker

    private var scopePicker: some View {
        HStack(spacing: 8) {
            ForEach(TaskScope.allCases) { scope in
                scopeCapsule(scope)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-scope-picker")
    }

    private func scopeCapsule(_ scope: TaskScope) -> some View {
        let isSelected = selectedScope == scope

        return Button {
            guard selectedScope != scope else { return }
            withAnimation(reduceMotion ? nil : PeekabooMotion.quick) {
                selectedScope = scope
            }
        } label: {
            Text(scope.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? Color(uiColor: .systemBackground) : Color.secondary)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(
                    Color.primary.opacity(isSelected ? 0.9 : 0.05),
                    in: Capsule(style: .continuous)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scope.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("task-scope-\(scope.rawValue)")
    }

    // MARK: Task list

    private func taskList(snapshot: TaskScopeSnapshot) -> some View {
        List {
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
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                        }
                        .onMove { source, destination in
                            move(within: section.tasks, from: source, to: destination)
                        }
                    } header: {
                        Text("\(section.status.title) · \(section.tasks.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(nil)
                            .contentTransition(.numericText())
                            .accessibilityIdentifier("task-section-\(section.status.rawValue)")
                    }
                    .listSectionSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollIndicators(.never)
        .refreshable { await refresh() }
        .safeAreaInset(edge: .bottom) { addTaskButton }
    }

    // Maps List onMove indices to TaskStore.reorder, which only accepts drops
    // on a task with the same status and priority (same rule as on macOS).
    private func move(within tasks: [TaskItem], from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first,
              sourceIndex != destination,
              sourceIndex + 1 != destination else { return }

        let moved = tasks[sourceIndex]
        let target = destination > sourceIndex ? tasks[destination - 1] : tasks[destination]
        // No withAnimation here: the row is already at its target from the
        // interactive move; animating the data change makes the List re-diff
        // against the in-flight drop and can leave it in the wrong state.
        if !store.reorder(taskID: moved.id, relativeTo: target.id) {
            // Rejected drop (e.g. across priorities). The List already moved the
            // row visually; wait for UIKit's drop animation to settle, then
            // spring the row back to the real order instead of jumping mid-flight.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(reduceMotion ? nil : PeekabooMotion.spring) {
                    store.objectWillChange.send()
                }
            }
        }
    }

    private var addTaskButton: some View {
        Button {
            editor = .create(selectedScope.creationStatus)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color(uiColor: .systemBackground))
                .frame(width: 60, height: 60)
                .background(Color.primary.opacity(0.9), in: Circle())
                .contentShape(Circle())
                .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 8)
        .accessibilityLabel(selectedScope.newItemTitle)
        .accessibilityIdentifier("add-task-button")
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Text(selectedScope.emptyStateTitle)
                .font(.system(size: 15, weight: .medium, design: .rounded))
            Text(selectedScope == .tasks
                ? "Add a task and it will appear on your Mac too."
                : "Capture an idea and promote it when you're ready.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 4) {
            if let message = store.lastErrorMessage {
                Text(message)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            if case .available = iCloudAvailability,
               let message = store.cloudSyncStatus.lastErrorMessage {
                Text(message)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            HStack(spacing: 5) {
                Image(systemName: syncSymbol)
                    .font(.system(size: 10, weight: .medium))
                Text(syncTitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var syncSymbol: String {
        switch iCloudAvailability {
        case .available: store.cloudSyncStatus.symbolName
        case .checking: "icloud"
        case .noAccount, .restricted, .temporarilyUnavailable, .unavailable:
            "exclamationmark.icloud"
        }
    }

    private var syncTitle: String {
        switch iCloudAvailability {
        case .available: store.cloudSyncStatus.title
        case .checking, .noAccount, .restricted, .temporarilyUnavailable, .unavailable:
            iCloudAvailability.title
        }
    }
}
