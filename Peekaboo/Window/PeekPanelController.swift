import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class PeekPanelController {
    private let panel: PeekPanel
    private let hostingView: NSHostingView<PeekPanelView>
    private let store: TaskStore
    private let settings: AppSettings
    private let uiState: PanelUIState
    private var cancellables: Set<AnyCancellable> = []
    private var isShowing = false
    private var needsResizeAfterShowing = false
    private var transitionGeneration = 0
    private(set) var currentScreen: NSScreen?
    private(set) var currentCorner: ScreenCorner = .topRight

    init(store: TaskStore, settings: AppSettings, uiState: PanelUIState) {
        self.store = store
        self.settings = settings
        self.uiState = uiState

        panel = PeekPanel(
            contentRect: CGRect(x: 0, y: 0, width: PanelGeometry.panelWidth, height: PanelGeometry.minimumHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        hostingView = NSHostingView(rootView: PeekPanelView(store: store, uiState: uiState, settings: settings))

        configurePanel()
        bindContentSize()
    }

    var visibleFrame: CGRect? {
        panel.isVisible ? panel.frame : nil
    }

    func show(on screen: NSScreen, corner: ScreenCorner, makeKey: Bool = false) {
        currentScreen = screen
        currentCorner = corner

        let finalFrame = frame(on: screen, corner: corner)

        if panel.isVisible {
            if makeKey {
                panel.makeKeyAndOrderFront(nil)
            } else {
                panel.orderFrontRegardless()
            }
            panel.alphaValue = 1

            guard !framesMatch(panel.frame, finalFrame) else { return }
            animateShow(to: finalFrame, fadeIn: false)
            return
        }

        let initialFrame = PanelGeometry.hiddenFrame(from: finalFrame, corner: corner)
        panel.setFrame(initialFrame, display: true)
        panel.alphaValue = 0

        if makeKey {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }

        animateShow(to: finalFrame, fadeIn: true)
    }

    private func animateShow(to finalFrame: CGRect, fadeIn: Bool) {
        transitionGeneration += 1
        let generation = transitionGeneration
        isShowing = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
            panel.animator().setFrame(finalFrame, display: true)
            if fadeIn { panel.animator().alphaValue = 1 }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard generation == self.transitionGeneration else { return }
                self.isShowing = false
                if self.needsResizeAfterShowing {
                    self.needsResizeAfterShowing = false
                    self.resizeAndReanchor()
                }
            }
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        transitionGeneration += 1
        let generation = transitionGeneration
        isShowing = false
        needsResizeAfterShowing = false
        let targetFrame = PanelGeometry.hiddenFrame(from: panel.frame, corner: currentCorner)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
            panel.animator().setFrame(targetFrame, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.transitionGeneration else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
    }

    private func configurePanel() {
        panel.contentView = hostingView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    private func bindContentSize() {
        Publishers.CombineLatest4(
            store.$tasks,
            uiState.$isComposerPresented,
            settings.$corner,
            uiState.$selectedScope
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, corner, _ in
                guard let self else { return }
                self.currentCorner = corner
                self.resizeAndReanchor()
            }
            .store(in: &cancellables)
    }

    private func resizeAndReanchor() {
        guard let screen = currentScreen else { return }
        if isShowing {
            needsResizeAfterShowing = true
            return
        }
        let targetFrame = frame(on: screen, corner: currentCorner)
        guard !framesMatch(panel.frame, targetFrame) else { return }
        if panel.isVisible {
            panel.setFrame(targetFrame, display: true, animate: true)
        } else {
            panel.setFrame(targetFrame, display: false)
        }
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.5
            && abs(lhs.minY - rhs.minY) < 0.5
            && abs(lhs.width - rhs.width) < 0.5
            && abs(lhs.height - rhs.height) < 0.5
    }

    private func frame(on screen: NSScreen, corner: ScreenCorner) -> CGRect {
        let statuses = uiState.selectedScope.statuses
        let sectionCount = statuses.reduce(into: 0) { count, status in
            if !store.orderedTasks(for: status).isEmpty { count += 1 }
        }
        let taskCount = store.tasks.filter { statuses.contains($0.status) }.count
        let height = PanelGeometry.preferredHeight(
            taskCount: taskCount,
            sectionCount: sectionCount,
            isComposing: uiState.isComposerPresented
        )
        return PanelGeometry.panelFrame(
            in: screen.visibleFrame,
            size: CGSize(width: PanelGeometry.panelWidth, height: height),
            corner: corner
        )
    }
}
