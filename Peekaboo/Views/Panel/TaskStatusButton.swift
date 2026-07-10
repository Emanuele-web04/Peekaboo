import SwiftUI

struct TaskStatusButton: View {
    let status: TaskStatus
    let priority: TaskPriority
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                TaskStatusMark(status: status, priority: priority)
                    .id(status)
                    .transition(.scale(scale: 0.65).combined(with: .opacity))
            }
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(status.primaryActionTitle)
        .animation(reduceMotion ? nil : PeekabooMotion.spring, value: status)
        .accessibilityLabel(status.primaryActionTitle)
        .accessibilityValue("\(priority.title) priority")
    }
}
