import SwiftUI

@main
struct PeakabooApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let coordinator = AppCoordinator.shared

    var body: some Scene {
        MenuBarExtra("Peakaboo", systemImage: "eye") {
            MenuBarView(store: coordinator.store, coordinator: coordinator)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                settings: coordinator.settings,
                loginItemService: coordinator.loginItemService
            )
        }
    }
}
