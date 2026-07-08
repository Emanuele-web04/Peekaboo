import SwiftUI

struct TaskSectionView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var uiState: PanelUIState
    let status: TaskStatus
    let tasks: [TaskItem]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Text("\(status.title.lowercased()) · \(tasks.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer()
            }
            .frame(height: 24)
            .padding(.horizontal, 4)

            ForEach(tasks) { task in
                TaskRowView(store: store, uiState: uiState, task: task)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .scale(scale: 0.96).combined(with: .opacity)
                        )
                    )
            }
        }
        .animation(reduceMotion ? nil : PeakabooMotion.spring, value: tasks.map(\.id))
    }
}
