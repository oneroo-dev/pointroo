import Foundation

/// `Pointroo --hook-stop`: a Claude Code Stop hook. When items wait for the project in the hook's `cwd`, it blocks the stop
/// and tells the agent to fetch them. It never takes items itself.
enum HookStop {
    static func output(openCount: Int, stopHookActive: Bool = false) -> String? {
        guard openCount > 0, !stopHookActive else { return nil }
        let reason = "\(openCount) new Pointroo item(s) for this project. Call get_open_items (pointroo MCP), do them, mark_done each."
        guard let data = try? JSONSerialization.data(withJSONObject: ["decision": "block", "reason": reason], options: [.withoutEscapingSlashes]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func run() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let json = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any]
        let cwd = json?["cwd"] as? String ?? FileManager.default.currentDirectoryPath
        let active = json?["stop_hook_active"] as? Bool ?? false
        if active { return }
        let count = Items.openItems(limit: 100, take: false, agent: "hook", project: cwd, unrouted: .never).count
        if let line = output(openCount: count, stopHookActive: active) { print(line) }
    }
}
