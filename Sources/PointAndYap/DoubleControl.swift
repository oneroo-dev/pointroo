import AppKit

/// Control gestures anywhere (global monitors need Accessibility, which the app has):
/// two taps of Control alone toggles, and with "hold to talk" on, holding Control alone for 0.5 s talks until release.
@MainActor
final class DoubleControl {
    private var monitors: [Any] = []
    private var gesture = KeyGesture()
    private var holdTimer: DispatchWorkItem?
    /// True only when our own holdStart began a recording, so holdEnd never stops one the user started another way.
    private var holdStartedRecording = false
    private let fire: () -> Void
    private let escape: () -> Void
    private let holdStart: () -> Bool
    private let holdEnd: () -> Void

    /// `holdStart` returns true when it really began a recording.
    init(fire: @escaping () -> Void, escape: @escaping () -> Void,
         holdStart: @escaping () -> Bool = { false }, holdEnd: @escaping () -> Void = {}) {
        self.fire = fire
        self.escape = escape
        self.holdStart = holdStart
        self.holdEnd = holdEnd
        let flags: (NSEvent) -> Void = { [weak self] e in MainActor.assumeIsolated { self?.flags(e) } }
        let other: (NSEvent) -> Void = { [weak self] e in
            MainActor.assumeIsolated {
                if e.type == .keyDown, e.keyCode == 53 {   // Esc
                    self?.escapePressed()
                } else {
                    self?.otherInput(e)
                }
            }
        }
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: other) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { flags($0); return $0 }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { other($0); return $0 }) { monitors.append(m) }
    }

    private func cancelTimer() {
        holdTimer?.cancel()
        holdTimer = nil
    }

    private func otherInput(_ event: NSEvent) {
        cancelTimer()
        gesture.otherInput(at: event.timestamp)
    }

    private func escapePressed() {
        cancelTimer()
        gesture.escape()
        holdStartedRecording = false
        escape()
    }

    private func flags(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let time = event.timestamp
        if mods == .control {
            handle(gesture.controlDown(at: time, holdToTalk: Prefs.holdToTalk))
            armTimer()
        } else if mods.isEmpty {
            cancelTimer()
            handle(gesture.controlUp(at: time))
        } else {
            cancelTimer()
            gesture.otherInput(at: time)
        }
    }

    private func armTimer() {
        guard Prefs.holdToTalk, holdTimer == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.holdTimer = nil
                self.handle(self.gesture.holdElapsed(at: ProcessInfo.processInfo.systemUptime))
            }
        }
        holdTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + KeyGesture.holdDelay, execute: item)
    }

    private func handle(_ actions: [KeyGestureAction]) {
        for action in actions {
            switch action {
            case .toggle:
                fire()
            case .holdStart:
                holdStartedRecording = holdStart()
            case .holdEnd:
                if holdStartedRecording { holdEnd() }
                holdStartedRecording = false
            }
        }
    }
}
