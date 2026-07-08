import AppKit
import Foundation

@MainActor
final class DailyCleanupService {
    private let store: TaskStore
    private let now: () -> Date
    private let calendar: () -> Calendar
    private var timer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private var workspaceTokens: [NSObjectProtocol] = []

    init(
        store: TaskStore,
        now: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { .autoupdatingCurrent }
    ) {
        self.store = store
        self.now = now
        self.calendar = calendar
    }

    func start() {
        guard notificationTokens.isEmpty, workspaceTokens.isEmpty else { return }

        let center = NotificationCenter.default
        let refreshNotifications: [Notification.Name] = [
            .NSCalendarDayChanged,
            .NSSystemTimeZoneDidChange,
            NSApplication.didBecomeActiveNotification
        ]
        notificationTokens = refreshNotifications.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cleanupAndReschedule() }
            }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            workspaceCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.cleanupAndReschedule() }
            }
        ]

        cleanupAndReschedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
        notificationTokens.removeAll()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceTokens.forEach(workspaceCenter.removeObserver)
        workspaceTokens.removeAll()
    }

    @discardableResult
    func performCleanup(at date: Date? = nil) -> Int {
        let timestamp = date ?? now()
        let startOfToday = calendar().startOfDay(for: timestamp)
        return store.purgeCompleted(before: startOfToday)
    }

    private func cleanupAndReschedule() {
        let timestamp = now()
        performCleanup(at: timestamp)
        scheduleNextMidnight(after: timestamp)
    }

    private func scheduleNextMidnight(after date: Date) {
        timer?.invalidate()
        let activeCalendar = calendar()
        guard let nextDay = activeCalendar.date(byAdding: .day, value: 1, to: activeCalendar.startOfDay(for: date)) else {
            return
        }

        let nextTimer = Timer(fire: nextDay, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.cleanupAndReschedule() }
        }
        nextTimer.tolerance = 1
        RunLoop.main.add(nextTimer, forMode: .common)
        timer = nextTimer
    }
}
