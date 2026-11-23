import Foundation

extension Prefs {
    /// Hold Control alone for half a second to talk, let go to stop. Off until the user turns it on.
    static var holdToTalk: Bool { UserDefaults.standard.object(forKey: "holdToTalk") as? Bool ?? false }
}

/// What a Control gesture asks the app to do.
enum KeyGestureAction: Equatable {
    case toggle
    case holdStart
    case holdEnd
}

/// A pure state machine for the Control gestures. The caller feeds it events with explicit times (seconds),
/// so there are no clocks or timers in here. The caller runs a one-shot timer and calls `holdElapsed` when it fires.
struct KeyGesture {
    static let tapLimit: TimeInterval = 0.3
    static let doubleTapWindow: TimeInterval = 0.4
    static let holdDelay: TimeInterval = 0.5

    private var downAt: TimeInterval?
    private var lastTap: TimeInterval?
    private var holdArmed = false
    /// Another key or click came while Control was down, so this press can no longer be a tap or a hold.
    private var spoiled = false
    private(set) var isHolding = false

    /// Control went down alone. `holdToTalk` says whether this press may turn into a hold.
    mutating func controlDown(at time: TimeInterval, holdToTalk: Bool) -> [KeyGestureAction] {
        guard downAt == nil, !spoiled, !isHolding else { return [] }
        downAt = time
        holdArmed = holdToTalk
        return []
    }

    /// The hold timer fired. Starts the hold only if Control is still down alone for long enough.
    mutating func holdElapsed(at time: TimeInterval) -> [KeyGestureAction] {
        guard holdArmed, !spoiled, !isHolding, let started = downAt, time - started >= Self.holdDelay else { return [] }
        isHolding = true
        lastTap = nil
        return [.holdStart]
    }

    /// Control was released and no other modifier is down.
    mutating func controlUp(at time: TimeInterval) -> [KeyGestureAction] {
        defer { spoiled = false }
        if isHolding {
            clear()
            return [.holdEnd]
        }
        guard !spoiled, let started = downAt, time - started < Self.tapLimit else {
            clear()
            return []
        }
        downAt = nil
        holdArmed = false
        if let last = lastTap, time - last < Self.doubleTapWindow {
            lastTap = nil
            return [.toggle]
        }
        lastTap = time
        return []
    }

    /// Any other key, click, scroll or extra modifier. Before a hold starts it cancels the press.
    /// After a hold starts it changes nothing, because the user may type while talking.
    mutating func otherInput(at time: TimeInterval) {
        guard !isHolding else { return }
        if downAt != nil { spoiled = true }
        downAt = nil
        lastTap = nil
        holdArmed = false
    }

    /// Esc ends a hold without a holdEnd, because the app already cancelled the recording.
    mutating func escape() {
        let controlIsDown = downAt != nil || isHolding
        clear()
        if controlIsDown { spoiled = true }
    }

    private mutating func clear() {
        downAt = nil
        lastTap = nil
        holdArmed = false
        isHolding = false
    }
}
