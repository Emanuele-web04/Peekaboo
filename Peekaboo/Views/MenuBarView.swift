import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: TaskStore
    let coordinator: AppCoordinator

    var body: some View {
        Button("Show Peekaboo", systemImage: "eye") {
            coordinator.showPanel()
        }

        Button("New task", systemImage: "plus") {
            coordinator.showNewTask()
        }
        .keyboardShortcut(.space, modifiers: [.control, .option])

        Divider()

        HStack {
            Text("Active Tasks")
            Spacer()
            Text("\(activeTaskCount)")
                .foregroundStyle(.secondary)
        }

        Button {
            coordinator.openSettings()
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Peekaboo", systemImage: "power") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var activeTaskCount: Int {
        store.tasks.filter { TaskScope.tasks.countedStatuses.contains($0.status) }.count
    }
}
