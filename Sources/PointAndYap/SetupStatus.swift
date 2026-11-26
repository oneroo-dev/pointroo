import AVFoundation
import Foundation

/// The speech model download, as the Setup checklist shows it. `checking` is the time before the launch prewarm has an answer.
enum SpeechState: Equatable {
    case checking
    case downloading
    case ready
    case failed
}

/// A short message for the page's toast (the app sends it as the hint.show event).
struct Hint: Equatable {
    var message: String
    /// "ok", "muted" or "warn".
    var tone: String
    var actionLabel: String? = nil
    /// The setup.action id the button runs.
    var action: String? = nil

    static let noSession = Hint(message: "Not sent: no Claude session open.", tone: "warn")
    static let speechFailed = Hint(message: "Speech download failed.", tone: "warn", actionLabel: "Retry", action: "retrySpeech")

    static func portMoved(from busy: Int, to port: Int) -> Hint {
        Hint(message: "Port \(busy) was busy, Pointroo moved to \(port).", tone: "muted")
    }

    var dictionary: [String: Any] {
        var out: [String: Any] = ["message": message, "tone": tone]
        if let actionLabel { out["actionLabel"] = actionLabel }
        if let action { out["action"] = action }
        return out
    }
}

/// Everything the Setup checklist needs, as plain values. SetupStatus.read() fills it from the real Mac; tests fill it by hand.
struct SetupInputs: Equatable {
    var inApplications: Bool
    var microphone: Bool
    var screenRecording: Bool
    var accessibility: Bool
    /// Permissions that were asked for before and are still off (the page then says "Open System Settings").
    var denied: Set<String> = []
    var claudeFound: Bool
    var toolAdded: Bool
    var stopHookAdded: Bool
    var speech: SpeechState
    /// The Claude sessions in ~/.claude/sessions. Empty = the wake row is left out.
    var sessions: [ClaudeSessionEntry] = []
}

/// The Setup checklist. Each row is {id, state: "done" | "todo" | "busy", detail?, action?}. The page owns the words;
/// `detail` is "denied" or "failed" when the row needs different words, and `action` is the setup.action id its button runs.
enum SetupStatus {
    /// The ids setup.action accepts.
    static let actions = ["move", "allowMicrophone", "allowScreenRecording", "allowAccessibility",
                          "openMicrophoneSettings", "openScreenRecordingSettings", "openAccessibilitySettings",
                          "install", "connect", "addHook", "retrySpeech", "updateClaude"]

    static let askedKey = "setupAsked"

    static func rows(_ inputs: SetupInputs) -> [[String: Any]] {
        func row(_ id: String, done: Bool, action: String, detail: String? = nil) -> [String: Any] {
            var out: [String: Any] = ["id": id, "state": done ? "done" : "todo"]
            if !done {
                out["action"] = action
                if let detail { out["detail"] = detail }
            }
            return out
        }
        func permission(_ id: String, _ name: String, on: Bool, label: String) -> [String: Any] {
            if inputs.denied.contains(name), !on { return row(id, done: false, action: "open\(label)Settings", detail: "denied") }
            return row(id, done: on, action: "allow\(label)")
        }
        var rows: [[String: Any]] = [
            row("applications", done: inputs.inApplications, action: "move"),
            permission("microphone", "microphone", on: inputs.microphone, label: "Microphone"),
            permission("screenRecording", "screenRecording", on: inputs.screenRecording, label: "ScreenRecording"),
            permission("accessibility", "accessibility", on: inputs.accessibility, label: "Accessibility"),
            row("claudeCode", done: inputs.claudeFound, action: "install"),
            row("tool", done: inputs.toolAdded, action: "connect"),
            row("stopHook", done: inputs.stopHookAdded, action: "addHook"),
        ]
        switch inputs.speech {
        case .ready: rows.append(["id": "speech", "state": "done"])
        case .checking, .downloading: rows.append(["id": "speech", "state": "busy"])
        case .failed: rows.append(["id": "speech", "state": "todo", "detail": "failed", "action": "retrySpeech"])
        }
        if !inputs.sessions.isEmpty {
            rows.append(row("wake", done: inputs.sessions.contains { $0.messagingSocketPath != nil }, action: "updateClaude"))
        }
        return rows
    }

    /// The real Mac. Reads files and may run the login shell once (cached), so call it off the main thread.
    static func read(defaults: UserDefaults = .standard, speech: SpeechState = Transcriber.prewarmGate.state) -> [[String: Any]] {
        let asked = Set(defaults.stringArray(forKey: askedKey) ?? [])
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let screenRecording = CGPreflightScreenCaptureAccess()
        let accessibility = AXProbe.trusted
        var denied = asked
        if AVCaptureDevice.authorizationStatus(for: .audio) == .denied { denied.insert("microphone") }
        let inputs = SetupInputs(
            inApplications: AgentInstall.installed,
            microphone: microphone, screenRecording: screenRecording, accessibility: accessibility,
            denied: denied,
            claudeFound: AgentInstall.claudeCLI != nil,
            toolAdded: AgentInstall.status().first { $0.name == "Claude Code" }?.on ?? false,
            stopHookAdded: AgentInstall.hasStopHook(),
            speech: speech,
            sessions: SessionWake.entries(in: SessionWake.defaultFolder))
        return rows(inputs)
    }

    /// Remembers that the user was asked for a permission, so a later "no" shows "Open System Settings".
    static func markAsked(_ name: String, defaults: UserDefaults = .standard) {
        var asked = Set(defaults.stringArray(forKey: askedKey) ?? [])
        asked.insert(name)
        defaults.set(asked.sorted(), forKey: askedKey)
    }

    /// The System Settings pane address for a permission.
    static func settingsPane(_ name: String) -> String {
        let pane = ["microphone": "Privacy_Microphone", "screenRecording": "Privacy_ScreenCapture", "accessibility": "Privacy_Accessibility"][name] ?? "Privacy"
        return "x-apple.systempreferences:com.apple.preference.security?\(pane)"
    }

    /// The page the "Install Claude Code" and "Update Claude Code" buttons open.
    static let claudeInstallPage = "https://code.claude.com/docs/en/setup"
}
