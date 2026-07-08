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
                    .padding(.horizontal, PeakabooStyle.horizontalPadding)
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
                    .padding(.horizontal, PeakabooStyle.horizontalPadding)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .peekPanelSurface(translucent: settings.isTranslucent)
        .animation(reduceMotion ? nil : PeakabooMotion.spring, value: uiState.isComposerPresented)
        .animation(reduceMotion ? nil : PeakabooMotion.spring, value: store.tasks.map(\.id))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("peakaboo")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Text("· \(activeSubtitle)")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : PeakabooMotion.quick, value: activeSubtitle)

            Spacer()

            Menu {
                Button {
                    settings.isTranslucent = true
                } label: {
                    if settings.isTranslucent {
                        Label("Translucent", systemImage: "checkmark")
                    } else {
                        Label("Translucent", systemImage: "circle.lefthalf.filled")
                    }
                }

                Button {
                    settings.isTranslucent = false
                } label: {
                    if !settings.isTranslucent {
                        Label("Solid", systemImage: "checkmark")
                    } else {
                        Label("Solid", systemImage: "square.fill")
                    }
                }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.06), in: Circle())
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Panel appearance")
            .accessibilityLabel("Panel appearance")
            .accessibilityIdentifier("appearance-menu")

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
        .padding(.horizontal, PeakabooStyle.horizontalPadding)
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
            .padding(.horizontal, PeakabooStyle.horizontalPadding - 4)
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
