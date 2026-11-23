import AppKit
import CoreAudio
import CoreGraphics

extension Prefs {
    /// After a done banner shows, listen for a short follow-up with no key. Off until the user turns it on.
    static var listenAfterDone: Bool { UserDefaults.standard.object(forKey: "listenAfterDone") as? Bool ?? false }
}

/// What the listen window asks the app to do.
enum ListenAction: Equatable {
    case start
    case cancelSilently
    case stop
}

/// A pure state machine for the short listen window after a done banner. The caller feeds it events with explicit
/// times (seconds), so there are no clocks or timers in here. The caller reads the world into `Conditions` before the
/// recording opens the microphone, and calls `tick` about ten times a second while the window is open.
struct ListenWindow {
    struct Conditions: Equatable {
        var settingOn: Bool
        var phaseIdle: Bool
        /// Another app is already using the microphone (a call).
        var micBusyElsewhere: Bool
        /// Seconds since the user last touched the keyboard or mouse.
        var idleSeconds: Double
        /// The screen is locked or the display is asleep.
        var screenLocked: Bool
    }

    /// No speech by now (seconds after the window opened): cancel with nothing kept.
    static let noSpeechLimit: TimeInterval = 6
    /// This much silence after speech ends the recording.
    static let silenceLimit: TimeInterval = 1.2
    /// The window never records longer than this.
    static let maxLength: TimeInterval = 20
    /// The user has been away longer than this: do not listen.
    static let idleLimit: Double = 120
    /// Only the first banner in this span opens a window.
    static let bannerSpan: TimeInterval = 30
    /// Level (RMS, 0 to 1) that counts as sound, and how long it has to hold to count as speech.
    static let speechLevel: Float = 0.02
    static let speechHold: TimeInterval = 0.15

    private(set) var isListening = false
    private var openedAt: TimeInterval = 0
    private var loudSince: TimeInterval?
    private var lastLoud: TimeInterval = 0
    private var heardSpeech = false
    private var spanStart: TimeInterval?

    /// A done banner was shown at `time`.
    mutating func bannerShown(at time: TimeInterval, conditions: Conditions) -> [ListenAction] {
        let isFirstInSpan: Bool
        if let start = spanStart, time - start < Self.bannerSpan {
            isFirstInSpan = false
        } else {
            spanStart = time
            isFirstInSpan = true
        }
        guard isFirstInSpan, !isListening, conditions.settingOn, conditions.phaseIdle, !conditions.micBusyElsewhere,
              conditions.idleSeconds <= Self.idleLimit, !conditions.screenLocked else { return [] }
        isListening = true
        openedAt = time
        loudSince = nil
        lastLoud = time
        heardSpeech = false
        return [.start]
    }

    /// The microphone level (RMS) at `time`. Speech is a level above the threshold held for `speechHold`.
    mutating func level(_ value: Float, at time: TimeInterval) {
        guard isListening else { return }
        guard value > Self.speechLevel else {
            loudSince = nil
            return
        }
        if loudSince == nil { loudSince = time }
        lastLoud = time
        if let since = loudSince, time - since >= Self.speechHold { heardSpeech = true }
    }

    /// Time passed. Decides when to give up, stop after silence, or stop at the cap.
    mutating func tick(at time: TimeInterval) -> [ListenAction] {
        guard isListening else { return [] }
        if !heardSpeech, time - openedAt >= Self.noSpeechLimit {
            close()
            return [.cancelSilently]
        }
        if heardSpeech, time - lastLoud >= Self.silenceLimit || time - openedAt >= Self.maxLength {
            close()
            return [.stop]
        }
        return []
    }

    /// Esc. The window closes and nothing is kept.
    mutating func escape() -> [ListenAction] {
        guard isListening else { return [] }
        close()
        return [.cancelSilently]
    }

    /// The user started a recording themself, or a recording ended some other way. The window steps aside.
    mutating func userTookOver() { close() }

    private mutating func close() {
        isListening = false
        loudSince = nil
        heardSpeech = false
    }
}

/// Reads the Mac for the listen window's conditions. Each is a small, separate check.
enum ListenSystem {
    /// True when the input device Pointroo would record from is already running for another app.
    /// Read this before Pointroo opens the microphone, or it sees its own use.
    static func micBusyElsewhere() -> Bool {
        guard let device = AudioRecorder.recordingDevice() else { return false }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    /// Seconds since the last keyboard, mouse or trackpad event in this login session.
    static func idleSeconds() -> Double {
        guard let anyEvent = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }

    /// True when the screen is locked or the main display is asleep.
    static func screenLocked() -> Bool {
        if CGDisplayIsAsleep(CGMainDisplayID()) != 0 { return true }
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (session["CGSSessionScreenIsLocked"] as? Bool) == true
    }
}
