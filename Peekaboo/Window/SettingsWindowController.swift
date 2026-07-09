import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private var hasPositionedWindow = false

    init(settings: AppSettings, loginItemService: LoginItemService, agentServer: AgentServer) {
        let rootView = SettingsView(
            settings: settings,
            loginItemService: loginItemService,
            agentServer: agentServer
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)

        window.title = "Peekaboo Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 520, height: 800))
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }

        if !hasPositionedWindow {
            window.center()
            hasPositionedWindow = true
        }

        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
