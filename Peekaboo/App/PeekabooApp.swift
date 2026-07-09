import SwiftUI

@main
struct PeekabooApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let coordinator = AppCoordinator.shared

    var body: some Scene {
        MenuBarExtra("Peekaboo", systemImage: "eye") {
            MenuBarView(store: coordinator.store, coordinator: coordinator)
        }
        .menuBarExtraStyle(.menu)
    }
}
