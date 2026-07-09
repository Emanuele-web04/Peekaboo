import AppKit
import Combine
import SwiftData

@MainActor
final class AppCoordinator {
    static let shared = AppCoordinator()

    let settings: AppSettings
    let store: TaskStore
    let loginItemService: LoginItemService
    let uiState: PanelUIState

    private let cleanupService: DailyCleanupService
    private let panelController: PeekPanelController
    private let settingsWindowController: SettingsWindowController
    private let hoverMonitor: CornerHoverMonitor
    private let agentServer: AgentServer
    private let isUITesting: Bool
    private let isRunningTests: Bool
    private var menuNotificationTokens: [NSObjectProtocol] = []
    private var agentAccessObservation: AnyCancellable?
    private var hasStarted = false
    private lazy var newTaskHotKey = GlobalHotKey { [weak self] in
        self?.showNewTask()
    }

    private init() {
        let environment = ProcessInfo.processInfo.environment
        isUITesting = environment["PEEKABOO_UI_TESTING"] == "1"
        isRunningTests = environment["PEEKABOO_TESTING"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil

        let settings = AppSettings()
        let container: ModelContainer
        do {
            container = try PersistenceController.makeContainer(
                inMemory: isUITesting || isRunningTests
            )
        } catch let cloudError {
            do {
                container = try PersistenceController.makeContainer(
                    inMemory: isUITesting || isRunningTests,
                    cloudSyncEnabled: false
                )
                settings.reportCloudSyncStartupFailure(cloudError.localizedDescription)
            } catch {
                fatalError(
                    "Unable to create the SwiftData container with CloudKit "
                        + "(\(cloudError)) or local-only (\(error))"
                )
            }
        }

        let store = TaskStore(container: container)
        let uiState = PanelUIState()
        let loginItemService = LoginItemService()
        let agentServer = AgentServer(
            port: settings.agentServerPort,
            handler: MCPRequestHandler(tools: AgentTaskTools(store: store))
        )
        let settingsWindowController = SettingsWindowController(
            settings: settings,
            loginItemService: loginItemService,
            agentServer: agentServer
        )
        let panelController = PeekPanelController(store: store, settings: settings, uiState: uiState)

        self.settings = settings
        self.store = store
        self.uiState = uiState
        self.panelController = panelController
        self.loginItemService = loginItemService
        self.settingsWindowController = settingsWindowController
        self.agentServer = agentServer
        cleanupService = DailyCleanupService(store: store)
        hoverMonitor = CornerHoverMonitor(
            settings: settings,
            panelController: panelController,
            uiState: uiState,
            store: store
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        observeMenuTracking()
        cleanupService.start()

        if isUITesting {
            hoverMonitor.keepVisibleForUITesting()
            return
        }

        newTaskHotKey.register()
        hoverMonitor.start()
        if !isRunningTests {
            agentAccessObservation = settings.$isAgentAccessEnabled.sink { [weak self] isEnabled in
                isEnabled ? self?.agentServer.start() : self?.agentServer.stop()
            }
        }
        if !settings.hasShownWelcome {
            settings.markWelcomeShown()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.openSettings()
            }
        }
    }

    func stop() {
        cleanupService.stop()
        hoverMonitor.stop()
        newTaskHotKey.unregister()
        agentAccessObservation = nil
        agentServer.stop()
        menuNotificationTokens.forEach(NotificationCenter.default.removeObserver)
        menuNotificationTokens.removeAll()
        hasStarted = false
    }

    func showPanel() {
        hoverMonitor.revealProgrammatically()
    }

    func showNewTask() {
        hoverMonitor.revealProgrammatically(openComposer: true, scope: .tasks)
    }

    func openSettings() {
        settingsWindowController.show()
    }

    private func observeMenuTracking() {
        let center = NotificationCenter.default
        menuNotificationTokens = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.uiState.isMenuTracking = true }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.uiState.isMenuTracking = false }
            }
        ]
    }
}
