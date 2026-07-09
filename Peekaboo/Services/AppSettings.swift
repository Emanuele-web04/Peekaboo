import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let corner = "selectedCorner"
        static let revealDelay = "revealDelay"
        static let hideDelay = "hideDelay"
        static let hasAdoptedFasterReveal = "hasAdoptedFasterReveal"
        static let hasAdoptedQuickerReveal = "hasAdoptedQuickerRevealV2"
        static let hasAdoptedInstantReveal = "hasAdoptedInstantRevealV3"
        static let hasShownWelcome = "hasShownWelcome"
        static let isTranslucent = "isTranslucent"
    }

    @Published var corner: ScreenCorner {
        didSet { defaults.set(corner.rawValue, forKey: Key.corner) }
    }

    @Published var isTranslucent: Bool {
        didSet { defaults.set(isTranslucent, forKey: Key.isTranslucent) }
    }

    @Published var revealDelay: Double {
        didSet {
            let clamped = Self.clamp(revealDelay, to: 0.2...2.0)
            if revealDelay != clamped {
                revealDelay = clamped
            } else {
                defaults.set(revealDelay, forKey: Key.revealDelay)
            }
        }
    }

    @Published var hideDelay: Double {
        didSet {
            let clamped = Self.clamp(hideDelay, to: 0.1...2.0)
            if hideDelay != clamped {
                hideDelay = clamped
            } else {
                defaults.set(hideDelay, forKey: Key.hideDelay)
            }
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        corner = ScreenCorner(rawValue: defaults.string(forKey: Key.corner) ?? "") ?? .topRight
        let storedDelay = defaults.object(forKey: Key.revealDelay) as? Double
        var resolvedDelay = storedDelay ?? 0.2
        if !defaults.bool(forKey: Key.hasAdoptedFasterReveal) {
            if abs(resolvedDelay - 0.5) < 0.001 {
                resolvedDelay = 0.4
                defaults.set(resolvedDelay, forKey: Key.revealDelay)
            }
            defaults.set(true, forKey: Key.hasAdoptedFasterReveal)
        }
        if !defaults.bool(forKey: Key.hasAdoptedQuickerReveal) {
            if storedDelay == nil || abs(resolvedDelay - 0.4) < 0.001 || abs(resolvedDelay - 0.5) < 0.001 {
                resolvedDelay = 0.3
                defaults.set(resolvedDelay, forKey: Key.revealDelay)
            }
            defaults.set(true, forKey: Key.hasAdoptedQuickerReveal)
        }
        if !defaults.bool(forKey: Key.hasAdoptedInstantReveal) {
            if storedDelay == nil || abs(resolvedDelay - 0.3) < 0.001 {
                resolvedDelay = 0.2
                defaults.set(resolvedDelay, forKey: Key.revealDelay)
            }
            defaults.set(true, forKey: Key.hasAdoptedInstantReveal)
        }
        revealDelay = Self.clamp(resolvedDelay, to: 0.2...2.0)
        let storedHideDelay = defaults.object(forKey: Key.hideDelay) as? Double
        hideDelay = Self.clamp(storedHideDelay ?? 0.3, to: 0.1...2.0)
        isTranslucent = (defaults.object(forKey: Key.isTranslucent) as? Bool) ?? true
    }

    var hasShownWelcome: Bool {
        defaults.bool(forKey: Key.hasShownWelcome)
    }

    func markWelcomeShown() {
        defaults.set(true, forKey: Key.hasShownWelcome)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
