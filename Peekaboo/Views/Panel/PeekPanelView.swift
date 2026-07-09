import SwiftUI

struct PeekPanelView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var uiState: PanelUIState
    @ObservedObject var settings: AppSettings

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            scopePicker

            if uiState.isComposerPresented {
                TaskComposerView(store: store, uiState: uiState)
                    .padding(.horizontal, PeekabooStyle.horizontalPadding)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if visibleTaskCount == 0 {
                emptyState
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                taskList
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
    }

    private var header: some View {
        ZStack {
            HStack(spacing: 8) {
                Text("Peekaboo")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("· \(activeSubtitle)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : PeekabooMotion.quick, value: activeSubtitle)
            }
            .lineLimit(1)

            HStack(spacing: 8) {
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
        .frame(maxWidth: .infinity)
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
                    weight: .medium,
                    design: .rounded
                ))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .frame(height: 22)
                .background(
                    Color.primary.opacity(isSelected ? 0.18 : 0.035),
                    in: Capsule(style: .continuous)
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            Color.primary.opacity(isSelected ? 0.38 : 0),
                            lineWidth: 0.6
                        )
                }
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

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                ForEach(uiState.selectedScope.statuses) { status in
                    let tasks = store.orderedTasks(for: status)
                    if !tasks.isEmpty {
                        TaskSectionView(store: store, uiState: uiState, status: status, tasks: tasks)
                    }
                }
            }
            .padding(.horizontal, PeekabooStyle.horizontalPadding - 4)
            .padding(.bottom, 14)
        }
        .scrollIndicators(.never)
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Text(uiState.selectedScope == .tasks ? "Nothing hiding here" : "No ideas waiting")
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

    private var activeSubtitle: String {
        let count = store.tasks.filter {
            uiState.selectedScope.countedStatuses.contains($0.status)
        }.count
        switch uiState.selectedScope {
        case .tasks:
            return count == 1 ? "1 active task" : "\(count) active tasks"
        case .backlog:
            return count == 1 ? "1 idea" : "\(count) ideas"
        }
    }

    private var visibleTaskCount: Int {
        store.tasks.filter { uiState.selectedScope.statuses.contains($0.status) }.count
    }

    private var newItemTitle: String {
        uiState.selectedScope == .tasks ? "New task" : "New backlog idea"
    }

}
