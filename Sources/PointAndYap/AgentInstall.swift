import Foundation

/// Registers the MCP server and the skill with the coding agents on this Mac, from /Applications. Adds, never overwrites:
/// an entry with our name that is not ours is left alone. It only ever touches entries named "pointroo": the entries and
/// skill links of Point and Yap ("pointandyap", "point-and-yap") are never read for changes, replaced or removed.
/// Each config is backed up before its first change.
enum AgentInstall {
    static let appPath = "/Applications/Pointroo.app"
    static let binary = "\(appPath)/Contents/MacOS/Pointroo"
    static let skill = "\(appPath)/Contents/Resources/skill/pointroo"
    static let server = "pointroo"
    static let skillName = "pointroo"
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Places the Claude Code CLI may be installed, in the order we look.
    static func cliCandidates(home: String) -> [String] {
        ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
         "\(home)/.claude/local/claude", "\(home)/.npm-global/bin/claude", "\(home)/.bun/bin/claude",
         "\(home)/.volta/bin/claude"]
    }

    /// The first candidate that is executable, else whatever the login shell says (only an absolute, executable path counts).
    static func resolveCLI(candidates: [String], isExecutable: (String) -> Bool, shellLookup: () -> String?) -> URL? {
        if let found = candidates.first(where: isExecutable) { return URL(fileURLWithPath: found) }
        guard let line = shellLookup()?.trimmingCharacters(in: .whitespacesAndNewlines),
              line.hasPrefix("/"), isExecutable(line) else { return nil }
        return URL(fileURLWithPath: line)
    }

    /// Runs `/bin/zsh -lc 'command -v claude'` with a time limit and returns the last output line, or nil.
    static func loginShellLookup(timeout: TimeInterval = 5) -> String? {
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Interactive login shell: nvm, fnm and similar set PATH in .zshrc, which a login-only shell skips.
        process.arguments = ["-lic", "command -v claude"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        if finished.wait(timeout: .now() + timeout) == .timedOut { process.terminate(); return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(separator: "\n").last.map(String.init)
    }

    private static let shellLookupLock = NSLock()
    nonisolated(unsafe) private static var shellLookupDone = false
    nonisolated(unsafe) private static var shellLookupResult: String?
    nonisolated(unsafe) private static var notFoundLogged = false

    /// The login-shell answer, asked once and kept.
    private static func cachedShellLookup() -> String? {
        shellLookupLock.lock()
        defer { shellLookupLock.unlock() }
        if !shellLookupDone { shellLookupResult = loginShellLookup(); shellLookupDone = true }
        return shellLookupResult
    }

    private static func logNotFoundOnce() {
        shellLookupLock.lock()
        defer { shellLookupLock.unlock() }
        guard !notFoundLogged else { return }
        notFoundLogged = true
        NSLog("pointroo: claude CLI not found")
    }

    /// The Claude Code CLI, only to register the MCP with it.
    static var claudeCLI: URL? {
        let found = resolveCLI(candidates: cliCandidates(home: home.path),
                               isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
                               shellLookup: cachedShellLookup)
        if found == nil { logNotFoundOnce() }
        return found
    }

    static var installed: Bool { Bundle.main.bundlePath == appPath }

    /// Whether to show the first-run question. A Mac where the app is already registered with an agent, or where the
    /// switch was set before the question existed, counts as answered, with what it already has.
    static func needsAsking() -> Bool {
        let d = UserDefaults.standard
        if d.bool(forKey: "agentsAsked") { return false }
        let found = status()
        if d.object(forKey: "connectAgents") != nil || found.contains(where: \.on) {
            if d.object(forKey: "connectAgents") == nil { d.set(true, forKey: "connectAgents") }
            d.set(true, forKey: "agentsAsked")
            return false
        }
        return !found.isEmpty
    }

    /// True while the question was never answered and the switch was never set (the launch check found no agent).
    static func shouldAskAgainOnActivate(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: "agentsAsked") && defaults.object(forKey: "connectAgents") == nil
    }

    static func run(force: Bool = false, log: (String) -> Void = { NSLog("pointroo: \($0)") }) {
        guard installed, force || Prefs.connectAgents else { return }
        claudeCode(log); stopHook(log: log); codex(log); cursor(log); skills(log)
    }

    /// Which agents on this Mac know the app (for Settings).
    static func status() -> [(name: String, on: Bool)] {
        var out: [(String, Bool)] = []
        let fm = FileManager.default
        let claude = home.appendingPathComponent(".claude.json")
        if fm.fileExists(atPath: claude.path) {
            let servers = (try? Data(contentsOf: claude)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["mcpServers"] as? [String: Any]
            out.append(("Claude Code", servers?[server] != nil))
        }
        if let t = try? String(contentsOf: home.appendingPathComponent(".codex/config.toml"), encoding: .utf8) {
            out.append(("Codex", t.contains("[mcp_servers.\(server)]")))
        }
        if fm.fileExists(atPath: home.appendingPathComponent(".cursor").path) {
            let j = (try? Data(contentsOf: home.appendingPathComponent(".cursor/mcp.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let servers = j?["mcpServers"] as? [String: Any]
            out.append(("Cursor", servers?[server] != nil))
        }
        return out
    }

    static func backup(_ file: URL, into folder: URL? = nil) {
        let dir = folder ?? Paths.support.appendingPathComponent("backups")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        try? FileManager.default.copyItem(at: file, to: dir.appendingPathComponent("\(file.lastPathComponent).\(f.string(from: Date()))"))
    }

    private static func claudeRun(_ args: [String], _ log: (String) -> Void) {
        guard let cli = claudeCLI else { return }
        let p = Foundation.Process()
        p.executableURL = cli
        p.arguments = args
        p.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); log("claude code \(args.prefix(2).joined(separator: " ")): exit \(p.terminationStatus)") }
        catch { log("claude code: \(error)") }
    }

    /// Claude Code: user scope through its own CLI (it owns ~/.claude.json).
    private static func claudeCode(_ log: (String) -> Void) {
        let cfg = home.appendingPathComponent(".claude.json")
        let servers = (try? Data(contentsOf: cfg)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["mcpServers"] as? [String: Any]
        guard servers?[server] == nil, claudeCLI != nil else { return }
        if FileManager.default.fileExists(atPath: cfg.path) { backup(cfg) }
        claudeRun(["mcp", "add", "--scope", "user", server, "--", binary, "--mcp"], log)
    }

    /// The Stop hook command, in the shape SKILL.md documents (the path is quoted).
    static let stopHookCommand = "\"\(binary)\" --hook-stop"

    /// Whether a Stop command is ours: it names the Pointroo binary and --hook-stop.
    static func isOurStopCommand(_ command: String) -> Bool {
        command.contains("Pointroo") && command.contains("--hook-stop")
    }

    /// The settings with our Stop hook added, or nil when nothing should change: we already have one, or the shape
    /// of "hooks" / "Stop" is not what we expect (then the file is left alone). Every other key stays as it is.
    static func mergingStopHook(into settings: [String: Any]) -> [String: Any]? {
        var result = settings
        var hooks: [String: Any] = [:]
        if let existing = settings["hooks"] {
            guard let dictionary = existing as? [String: Any] else { return nil }
            hooks = dictionary
        }
        var stop: [Any] = []
        if let existing = hooks["Stop"] {
            guard let list = existing as? [Any] else { return nil }
            stop = list
        }
        for entry in stop {
            let inner = (entry as? [String: Any])?["hooks"] as? [Any] ?? []
            for hook in inner {
                if let command = (hook as? [String: Any])?["command"] as? String, isOurStopCommand(command) { return nil }
            }
        }
        stop.append(["hooks": [["type": "command", "command": stopHookCommand]]])
        hooks["Stop"] = stop
        result["hooks"] = hooks
        return result
    }

    /// True when settings.json already has our Stop hook (the same test stopHook uses to skip). A missing or unreadable file is false.
    static func hasStopHook(settings: URL = AgentInstall.home.appendingPathComponent(".claude/settings.json")) -> Bool {
        guard let data = try? Data(contentsOf: settings),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return mergingStopHook(into: object) == nil
    }

    /// Adds the Stop hook to ~/.claude/settings.json (same consent as the MCP add). Backs the file up first. A file with
    /// bad JSON is left alone. When the file is missing it is made only if the ~/.claude folder exists.
    static func stopHook(settings: URL = AgentInstall.home.appendingPathComponent(".claude/settings.json"),
                         backups: URL? = nil, log: (String) -> Void = { NSLog("pointroo: \($0)") }) {
        let fm = FileManager.default
        var current: [String: Any] = [:]
        let existed = fm.fileExists(atPath: settings.path)
        if existed {
            guard let data = try? Data(contentsOf: settings),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                log("stop hook: settings.json is not a JSON object, left alone")
                return
            }
            current = object
        } else if !fm.fileExists(atPath: settings.deletingLastPathComponent().path) {
            return
        }
        guard let merged = mergingStopHook(into: current) else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
        if existed { backup(settings, into: backups) }
        do { try data.write(to: settings, options: .atomic); log("stop hook written") } catch { log("stop hook: \(error)") }
    }

    /// Codex: an [mcp_servers.pointroo] table in ~/.codex/config.toml.
    private static func codex(_ log: (String) -> Void) {
        let cfg = home.appendingPathComponent(".codex/config.toml")
        guard let before = try? String(contentsOf: cfg, encoding: .utf8) else { return }
        let text = addingCodexTable(to: before)
        guard text != before else { return }
        backup(cfg)
        do { try text.write(to: cfg, atomically: true, encoding: .utf8); log("codex mcp written") } catch { log("codex: \(error)") }
    }

    /// The config with our table added when it has none; every other table stays as it is.
    static func addingCodexTable(to text: String) -> String {
        guard !text.contains("[mcp_servers.\(server)]") else { return text }
        return text + (text.hasSuffix("\n") ? "" : "\n") + "\n[mcp_servers.\(server)]\ncommand = \"\(binary)\"\nargs = [\"--mcp\"]\n"
    }

    /// Cursor: mcpServers.pointroo in ~/.cursor/mcp.json.
    private static func cursor(_ log: (String) -> Void) {
        let cfg = home.appendingPathComponent(".cursor/mcp.json")
        guard FileManager.default.fileExists(atPath: home.appendingPathComponent(".cursor").path) else { return }
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: cfg) {
            guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }  // unreadable: leave it
            json = j
        }
        var servers = json["mcpServers"] as? [String: Any] ?? [:]
        guard servers[server] == nil else { return }
        if FileManager.default.fileExists(atPath: cfg.path) { backup(cfg) }
        servers[server] = ["command": binary, "args": ["--mcp"]]
        json["mcpServers"] = servers
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            try? data.write(to: cfg, options: .atomic); log("cursor mcp written")
        }
    }

    /// The skill as a link into the app bundle, in Claude Code's and the shared skills folder.
    private static func skills(_ log: (String) -> Void) { linkSkills(home: home, skillPath: skill, log: log) }

    /// ~/.claude/skills is made when ~/.claude exists; ~/.agents/skills is only used when it already exists.
    static func linkSkills(home: URL, skillPath skill: String, log: (String) -> Void) {
        let fm = FileManager.default
        for folder in [".claude/skills", ".agents/skills"] {
            let parent = home.appendingPathComponent(folder)
            if folder == ".claude/skills", !fm.fileExists(atPath: parent.path),
               fm.fileExists(atPath: home.appendingPathComponent(".claude").path) {
                try? fm.createDirectory(at: parent, withIntermediateDirectories: false)
            }
            guard fm.fileExists(atPath: parent.path) else { continue }
            let link = parent.appendingPathComponent(skillName)
            if let dest = try? fm.destinationOfSymbolicLink(atPath: link.path) {
                if dest == skill { continue }
                if dest.hasSuffix("/Contents/Resources/skill/\(skillName)") { try? fm.removeItem(at: link) } else { continue }
            } else if fm.fileExists(atPath: link.path) { continue }   // someone else's folder of that name
            do { try fm.createSymbolicLink(atPath: link.path, withDestinationPath: skill); log("skill linked in \(folder)") }
            catch { log("skill \(folder): \(error)") }
        }
    }
}
