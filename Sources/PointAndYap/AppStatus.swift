import AVFoundation
import CoreGraphics
import Foundation

/// What the Settings screen shows: the MCP server line and the three permissions.
struct AppStatus: Equatable {
    var mcpRunning: Bool
    var mcpPort: Int
    var mcpText: String
    var sessions: Int
    var agents: [String]
    var microphone: Bool
    var screenRecording: Bool
    var accessibility: Bool
    /// The headless agent runs that auto-start has going now.
    var autoRuns: [AutoStart.Run] = []
    /// The last auto-start run that ended (nil until one did).
    var lastAutoRun: AutoStart.LastRun?

    /// The words permissions.ask accepts.
    static let permissionNames = ["microphone", "screenRecording", "accessibility"]

    /// Builds a status from plain inputs. Nothing here touches a socket or the permission system, so tests can call it.
    /// The port shown is the bound port when the server runs, else the configured one.
    static func make(boundPort: Int, configuredPort: Int, text: String, live: [LiveSession],
                     microphone: Bool, screenRecording: Bool, accessibility: Bool,
                     autoRuns: [AutoStart.Run] = [], lastAutoRun: AutoStart.LastRun? = nil) -> AppStatus {
        AppStatus(mcpRunning: boundPort != 0,
                  mcpPort: boundPort != 0 ? boundPort : configuredPort,
                  mcpText: text,
                  sessions: live.count,
                  agents: Array(Set(live.map(\.agent))).sorted(),
                  microphone: microphone, screenRecording: screenRecording, accessibility: accessibility,
                  autoRuns: autoRuns, lastAutoRun: lastAutoRun)
    }

    /// The real values: the listener's statics and the running sessions (this reads the disk). The three permission values
    /// are passed in, so the caller decides how to read them (AppState.refreshAccess reads the same three).
    static func current(microphone: Bool, screenRecording: Bool, accessibility: Bool) -> AppStatus {
        make(boundPort: Int(MCPListener.boundPort), configuredPort: Int(MCPListener.mcpPort), text: MCPListener.status,
             live: LiveSessions.all(),
             microphone: microphone, screenRecording: screenRecording, accessibility: accessibility,
             autoRuns: AutoStart.shared.runs, lastAutoRun: AutoStart.shared.lastRun)
    }

    /// Reads everything now, including the permissions (the same three calls AppState.refreshAccess makes). Real system calls: tests must not use it.
    static func readNow() -> AppStatus {
        current(microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                screenRecording: CGPreflightScreenCaptureAccess(),
                accessibility: AXProbe.trusted)
    }

    var dictionary: [String: Any] {
        var result: [String: Any] = ["mcpRunning": mcpRunning, "mcpPort": mcpPort, "mcpText": mcpText, "sessions": sessions, "agents": agents,
                                     "microphone": microphone, "screenRecording": screenRecording, "accessibility": accessibility,
                                     "autoRuns": autoRuns.map(\.dictionary)]
        if let lastAutoRun { result["lastAutoRun"] = lastAutoRun.dictionary }
        return result
    }
}
