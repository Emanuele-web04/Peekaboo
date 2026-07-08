import SwiftUI

struct TaskStatusButton: View {
    let status: TaskStatus
    let priority: TaskPriority
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                statusMark
                    .id(status)
                    .transition(.scale(scale: 0.65).combined(with: .opacity))
            }
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(status == .done ? "Move back to To do" : "Mark done")
        .animation(reduceMotion ? nil : PeakabooMotion.spring, value: status)
    }

    private var statusMark: some View {
        ZStack {
            switch status {
            case .todo:
                Circle()
                    .stroke(priority.color, lineWidth: 1.5)
                    .frame(width: 15, height: 15)
            case .inProgress:
                Circle()
                    .stroke(priority.color, lineWidth: 1.5)
                    .frame(width: 15, height: 15)
                // Linear-style half pie: fills most of the ring, thin gap in between.
                Circle()
                    .trim(from: 0, to: 0.5)
                    .rotation(.degrees(90))
                    .fill(priority.color)
                    .frame(width: 10.5, height: 10.5)
            case .done:
                Circle()
                    .fill(priority.color)
                    .frame(width: 15, height: 15)
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel(status == .done ? "Move back to To do" : "Mark done")
        .accessibilityValue("\(priority.title) priority")
    }
}
