import SwiftUI

struct PeekPanelView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var uiState: PanelUIState
    @ObservedObject var settings: AppSettings

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let statusOrder: [TaskStatus] = [.inProgress, .todo, .done]

    var body: some View {
        VStack(spacing: 0) {
            header

            if uiState.isComposerPresented {
                TaskComposerView(store: store, uiState: uiState)
                    .padding(.horizontal, PeekabooStyle.horizontalPadding)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if store.tasks.isEmpty {
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
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("peekaboo")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("· \(activeSubtitle)")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : PeekabooMotion.quick, value: activeSubtitle)

            Spacer()

            Button {
                AppCoordinator.shared.openSettings()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
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
            .help(uiState.isComposerPresented ? "Cancel" : "New task")
            .accessibilityLabel(uiState.isComposerPresented ? "Cancel" : "New task")
            .accessibilityIdentifier("add-task-button")
        }
        .padding(.horizontal, PeekabooStyle.horizontalPadding)
        .frame(height: 44)
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 7) {
                ForEach(statusOrder) { status in
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
            Text("Nothing hiding here")
                .font(.system(size: 13, weight: .medium, design: .rounded))
            Text("Add a task and it will stay close by.")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 18)
    }

    private var activeSubtitle: String {
        let activeCount = store.tasks.filter { $0.status != .done }.count
        return activeCount == 1 ? "1 active task" : "\(activeCount) active tasks"
    }
}
