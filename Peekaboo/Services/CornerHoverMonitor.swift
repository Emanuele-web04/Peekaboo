import AppKit
import SwiftUI

enum MouseButtonState {
    static func isPrimaryPressed(in pressedMouseButtons: Int) -> Bool {
        (pressedMouseButtons & 1) != 0
    }
}

@MainActor
final class CornerHoverMonitor {
    private let settings: AppSettings
    private let panelController: PeekPanelController
    private let uiState: PanelUIState
    private let store: TaskStore

    private var stateMachine = CornerHoverStateMachine()
    private var pollingTimer: DispatchSourceTimer?
    private var screenChangeToken: NSObjectProtocol?
    private var responsivenessActivity: NSObjectProtocol?
    private var revealRefreshTask: Task<Void, Never>?

    init(
        settings: AppSettings,
        panelController: PeekPanelController,
        uiState: PanelUIState,
        store: TaskStore
    ) {
        self.settings = settings
        self.panelController = panelController
        self.uiState = uiState
        self.store = store
    }

    func start() {
        guard pollingTimer == nil else { return }

        responsivenessActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Keep the configured Peekaboo corner responsive"
        )

        // A coalesced 20 Hz sample keeps the corner responsive without tracking raw mouse events.
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(
            deadline: .now(),
            repeating: .milliseconds(50),
            leeway: .milliseconds(15)
        )
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.samplePointer() }
        }
        pollingTimer = timer
        timer.resume()

        screenChangeToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.samplePointer() }
        }
    }

    func stop() {
        pollingTimer?.cancel()
        pollingTimer = nil
        revealRefreshTask?.cancel()
        revealRefreshTask = nil
        if let screenChangeToken { NotificationCenter.default.removeObserver(screenChangeToken) }
        screenChangeToken = nil
        if let responsivenessActivity {
            ProcessInfo.processInfo.endActivity(responsivenessActivity)
            self.responsivenessActivity = nil
        }
        stateMachine.forceHidden()
        panelController.hide()
    }

    func revealProgrammatically(openComposer: Bool = false, scope: TaskScope? = nil) {
        guard let screen = screen(containing: NSEvent.mouseLocation) ?? NSScreen.main else { return }
        refreshStoreForReveal()
        if let scope { uiState.selectScope(scope) }
        if openComposer {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { uiState.beginAdding() }
        }
        stateMachine.forceVisible(at: ProcessInfo.processInfo.systemUptime, grace: 3)
        panelController.show(on: screen, corner: settings.corner, makeKey: openComposer)
    }

    func keepVisibleForUITesting(openComposer: Bool = false) {
        guard let screen = NSScreen.main else { return }
        if openComposer { uiState.beginAdding() }
        stateMachine.forceVisible(at: ProcessInfo.processInfo.systemUptime, grace: 86_400)
        panelController.show(on: screen, corner: settings.corner, makeKey: true)
    }

    private func samplePointer() {
        let location = NSEvent.mouseLocation
        let activeScreen = screen(containing: location)
        // When the cursor is pinned against a screen edge, mouseLocation sits exactly on
        // the frame boundary (e.g. y == maxY at the top), which CGRect.contains excludes.
        // Expand the hotspot outward so edge-pinned coordinates still count as inside.
        let isInHotspot = activeScreen.map {
            PanelGeometry.hotspot(in: $0.frame, corner: settings.corner)
                .insetBy(dx: -1, dy: -1)
                .contains(location)
        } ?? false
        let isInPanel = panelController.visibleFrame?.contains(location) ?? false
        let isPrimaryMouseButtonPressed = MouseButtonState.isPrimaryPressed(
            in: NSEvent.pressedMouseButtons
        )
        if !isPrimaryMouseButtonPressed,
           let draggedTaskID = uiState.finishDragging(releasedOutsidePanel: !isInPanel) {
            store.startAfterExternalDrag(taskID: draggedTaskID)
        }

        let uptime = ProcessInfo.processInfo.systemUptime
        let transition = stateMachine.update(
            at: uptime,
            isInHotspot: isInHotspot,
            isInPanel: isInPanel,
            isInteractionLocked: uiState.isInteractionLocked || isPrimaryMouseButtonPressed,
            revealDelay: settings.revealDelay,
            hideDelay: settings.hideDelay
        )

        switch transition {
        case .none:
            break
        case .reveal:
            guard let activeScreen else { return }
            // Pull any CloudKit import out of SwiftData's context cache before
            // calculating the panel contents. This only runs on reveal, not on
            // the 20 Hz pointer sampling path.
            refreshStoreForReveal()
            panelController.show(on: activeScreen, corner: settings.corner)
        case .hide:
            panelController.hide()
        }
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            // Edge-pinned pointer coordinates can land exactly on frame.maxX, outside
            // every screen frame; tolerate a 1 pt overshoot so corners keep working.
            ?? NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
    }

    private func refreshStoreForReveal() {
        store.refresh()
        revealRefreshTask?.cancel()
        revealRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.store.refresh()
        }
    }
}
