import SwiftUI

struct TaskComposerView: View {
    @ObservedObject var store: TaskStore
    @ObservedObject var uiState: PanelUIState

    @State private var title = ""
    @State private var priority: TaskPriority = .none
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                TextField(placeholder, text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .rounded))
                    .focused($isTitleFocused)
                    .onSubmit(save)
                    .onExitCommand(perform: cancel)
                    .accessibilityIdentifier("new-task-title")

                Button(action: save) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(Color.accentColor, in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Add task")
                .accessibilityIdentifier("save-task")
            }

            HStack(spacing: 6) {
                ForEach(TaskPriority.allCases) { option in
                    let isSelected = priority == option

                    Button {
                        priority = option
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: option == .none ? "flag" : "flag.fill")
                                .font(.system(size: 8, weight: .semibold))
                            Text(option.title)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(option.color)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(
                            option.color.opacity(isSelected ? 0.18 : 0.035),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .stroke(
                                    option.color.opacity(isSelected ? 0.38 : 0),
                                    lineWidth: 0.6
                                )
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Priority: \(option.title)")
                    .accessibilityLabel("\(option.title) priority")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .accessibilityIdentifier("task-priority-chips")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 7)
        .frame(height: 62)
        .animation(PeekabooMotion.quick, value: priority)
        .onAppear(perform: focus)
    }

    private func focus() {
        DispatchQueue.main.async { isTitleFocused = true }
    }

    private func save() {
        guard store.create(
            title: title,
            priority: priority,
            status: uiState.selectedScope.creationStatus
        ) != nil else { return }
        title = ""
        priority = .none
        uiState.endAdding()
    }

    private func cancel() {
        title = ""
        priority = .none
        uiState.endAdding()
    }

    private var placeholder: String {
        uiState.selectedScope.composerPlaceholder
    }
}
