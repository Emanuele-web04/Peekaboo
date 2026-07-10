import SwiftUI

struct PeekPanelView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var uiState: PanelUIState
    @ObservedObject var settings: AppSettings

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let snapshot = store.snapshot(for: uiState.selectedScope)

        VStack(spacing: 0) {
            header(activeCount: snapshot.activeCount)
            scopePicker

            if uiState.isComposerPresented {
                TaskComposerView(store: store, uiState: uiState)
                    .padding(.horizontal, PeekabooStyle.horizontalPadding)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if snapshot.visibleCount == 0 {
                emptyState
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                taskList(sections: snapshot.sections)
                    .transition(.opacity)
            }

            if let error = store.lastErrorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(.horizontal, PeekabooStyle.horizontalPadding)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .peekPanelSurface(translucent: settings.isTranslucent)
        .animation(reduceMotion ? nil : PeekabooMotion.spring, value: uiState.isComposerPresented)
        .animation(reduceMotion ? nil : PeekabooMotion.spring, value: store.tasks.map(\.id))
        .animation(reduceMotion ? nil : PeekabooMotion.quick, value: uiState.selectedScope)
        .animation(reduceMotion ? nil : PeekabooMotion.quick, value: uiState.isDraggingTask)
    }

    private func header(activeCount: Int) -> some View {
        HStack(spacing: 8) {
            Text("Peekaboo")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("· \(activeSubtitle(count: activeCount))")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : PeekabooMotion.quick, value: activeCount)

            Spacer()

            Button {
                AppCoordinator.shared.openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings")
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings-button")

            Button {
                if uiState.isComposerPresented {
                    uiState.endAdding()
                } else {
                    uiState.beginAdding()
                }
            } label: {
                Image(systemName: uiState.isComposerPresented ? "xmark" : "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: Circle())
                    .contentShape(Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(uiState.isComposerPresented ? "Cancel" : newItemTitle)
            .accessibilityLabel(uiState.isComposerPresented ? "Cancel" : newItemTitle)
            .accessibilityIdentifier("add-task-button")
        }
        .padding(.horizontal, PeekabooStyle.horizontalPadding)
        .frame(height: 44)
    }

    private var scopePicker: some View {
        HStack(spacing: 6) {
            ForEach(TaskScope.allCases) { scope in
                scopeCapsule(scope)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PeekabooStyle.horizontalPadding)
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-scope-picker")
    }

    private func scopeCapsule(_ scope: TaskScope) -> some View {
        let isSelected = uiState.selectedScope == scope

        return Button {
            selectScope(scope)
        } label: {
            Text(scope.title)
                .font(.system(
                    size: 10,
                    weight: isSelected ? .semibold : .medium,
                    design: .rounded
                ))
                .foregroundStyle(
                    isSelected
                        ? Color(nsColor: .windowBackgroundColor)
                        : Color.secondary
                )
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(
                    Color.primary.opacity(isSelected ? 0.9 : 0.035),
                    in: Capsule(style: .continuous)
                )
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(scope.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("task-scope-\(scope.rawValue)")
    }

    private func selectScope(_ scope: TaskScope) {
        guard uiState.selectedScope != scope else { return }
        if reduceMotion {
            uiState.selectScope(scope)
        } else {
            withAnimation(PeekabooMotion.quick) {
                uiState.selectScope(scope)
            }
        }
    }

    private func taskList(sections: [TaskSectionSnapshot]) -> some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                ForEach(displaySections(from: sections)) { section in
                    TaskSectionView(
                        store: store,
                        uiState: uiState,
                        status: section.status,
                        tasks: section.tasks
                    )
                }
            }
            .padding(.horizontal, PeekabooStyle.horizontalPadding - 4)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.never)
    }

    /// While a task is being dragged, surface every section of the scope —
    /// including empty ones — so any status is reachable as a drop target.
    private func displaySections(from sections: [TaskSectionSnapshot]) -> [TaskSectionSnapshot] {
        guard uiState.isDraggingTask else { return sections }
        return uiState.selectedScope.statuses.map { status in
            sections.first { $0.status == status }
                ?? TaskSectionSnapshot(status: status, tasks: [])
        }
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Text(uiState.selectedScope.emptyStateTitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
            Text(uiState.selectedScope == .tasks
                ? "Add a task and it will stay close by."
                : "Capture an idea for later.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 18)
    }

    private func activeSubtitle(count: Int) -> String {
        uiState.selectedScope.activeSubtitle(count: count)
    }

    private var newItemTitle: String {
        uiState.selectedScope.newItemTitle
    }
}
