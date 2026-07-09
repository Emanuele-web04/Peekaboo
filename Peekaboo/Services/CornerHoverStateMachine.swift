import Foundation

struct CornerHoverStateMachine {
    enum Transition: Equatable {
        case none
        case reveal
        case hide
    }

    private(set) var isVisible = false
    private var hotspotEnteredAt: TimeInterval?
    private var revealedAt: TimeInterval?
    private var revealGrace: TimeInterval = 0.8
    private var panelHasBeenEntered = false
    private var leaveBeganAt: TimeInterval?

    mutating func update(
        at timestamp: TimeInterval,
        isInHotspot: Bool,
        isInPanel: Bool,
        isInteractionLocked: Bool,
        revealDelay: TimeInterval,
        hideDelay: TimeInterval = 0.3
    ) -> Transition {
        if !isVisible {
            guard isInHotspot else {
                hotspotEnteredAt = nil
                return .none
            }

            if hotspotEnteredAt == nil { hotspotEnteredAt = timestamp }
            guard timestamp - (hotspotEnteredAt ?? timestamp) >= revealDelay else { return .none }

            isVisible = true
            revealedAt = timestamp
            revealGrace = 0.8
            panelHasBeenEntered = false
            leaveBeganAt = nil
            hotspotEnteredAt = nil
            return .reveal
        }

        if isInteractionLocked || isInHotspot {
            leaveBeganAt = nil
            return .none
        }

        if isInPanel {
            panelHasBeenEntered = true
            leaveBeganAt = nil
            return .none
        }

        if !panelHasBeenEntered,
           let revealedAt,
           timestamp - revealedAt < revealGrace {
            return .none
        }

        if leaveBeganAt == nil {
            leaveBeganAt = timestamp
            return .none
        }

        guard timestamp - (leaveBeganAt ?? timestamp) >= max(0, hideDelay) else { return .none }
        reset()
        return .hide
    }

    mutating func forceVisible(at timestamp: TimeInterval, grace: TimeInterval = 3) {
        isVisible = true
        revealedAt = timestamp
        revealGrace = grace
        panelHasBeenEntered = false
        leaveBeganAt = nil
        hotspotEnteredAt = nil
    }

    mutating func forceHidden() {
        reset()
    }

    private mutating func reset() {
        isVisible = false
        hotspotEnteredAt = nil
        revealedAt = nil
        panelHasBeenEntered = false
        leaveBeganAt = nil
    }
}
