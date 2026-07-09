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

struct TaskStatusMark: View {
    let status: TaskStatus
    let priority: TaskPriority
    var size: CGFloat = 15

    var body: some View {
        ZStack {
            switch status {
            case .todo:
                Circle()
                    .stroke(priority.color, lineWidth: 1.5)
                    .frame(width: size, height: size)
            case .inProgress:
                Circle()
                    .stroke(priority.color, lineWidth: 1.5)
                    .frame(width: size, height: size)
                // Linear-style half pie: fills most of the ring, thin gap in between.
                Circle()
                    .trim(from: 0, to: 0.5)
                    .rotation(.degrees(90))
                    .fill(priority.color)
                    .frame(width: size * 0.7, height: size * 0.7)
            case .done:
                Circle()
                    .fill(priority.color)
                    .frame(width: size, height: size)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.47, weight: .bold))
                    .foregroundStyle(.white)
            case .backlog:
                Circle()
                    .stroke(
                        priority.color,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2.2, 2.2])
                    )
                    .frame(width: size, height: size)
            }
        }
    }
}
