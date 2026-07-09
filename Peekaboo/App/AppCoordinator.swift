import AppKit
import Carbon.HIToolbox
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
    private let isUITesting: Bool
    private var menuNotificationTokens: [NSObjectProtocol] = []
    private var hasStarted = false
    private lazy var newTaskHotKey = GlobalHotKey(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(controlKey | optionKey)
    ) { [weak self] in
        self?.showNewTask()
    }

    private init() {
        isUITesting = ProcessInfo.processInfo.environment["PEEKABOO_UI_TESTING"] == "1"

        let container: ModelContainer
        do {
            container = try PersistenceController.makeContainer(inMemory: isUITesting)
        } catch {
            fatalError("Unable to create the SwiftData container: \(error)")
        }

        let settings = AppSettings()
        let store = TaskStore(container: container)
        let uiState = PanelUIState()
        let loginItemService = LoginItemService()
        let settingsWindowController = SettingsWindowController(
            settings: settings,
            loginItemService: loginItemService
        )
        let panelController = PeekPanelController(store: store, settings: settings, uiState: uiState)

        self.settings = settings
        self.store = store
        self.uiState = uiState
        self.panelController = panelController
        self.loginItemService = loginItemService
        self.settingsWindowController = settingsWindowController
        cleanupService = DailyCleanupService(store: store)
        hoverMonitor = CornerHoverMonitor(
            settings: settings,
            panelController: panelController,
            uiState: uiState
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
        menuNotificationTokens.forEach(NotificationCenter.default.removeObserver)
        menuNotificationTokens.removeAll()
        hasStarted = false
    }

    func showPanel() {
        hoverMonitor.revealProgrammatically()
    }

    func showNewTask() {
        hoverMonitor.revealProgrammatically(openComposer: true)
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

@MainActor
private final class GlobalHotKey {
    private static let signature: OSType = 0x504B424F // "PKBO"

    private let keyCode: UInt32
    private let modifiers: UInt32
    private let action: @MainActor () -> Void
    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.action = action
    }

    func register() {
        guard hotKeyReference == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, context in
                guard let event, let context else { return noErr }

                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr, identifier.signature == GlobalHotKey.signature else {
                    return noErr
                }

                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            context,
            &eventHandlerReference
        )
        guard installStatus == noErr else { return }

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        if registerStatus != noErr {
            if let eventHandlerReference { RemoveEventHandler(eventHandlerReference) }
            eventHandlerReference = nil
        }
    }

    func unregister() {
        if let hotKeyReference { UnregisterEventHotKey(hotKeyReference) }
        if let eventHandlerReference { RemoveEventHandler(eventHandlerReference) }
        hotKeyReference = nil
        eventHandlerReference = nil
    }
}
