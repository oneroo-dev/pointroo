import Foundation

/// `PointAndYap --hook-stop`: a Claude Code Stop hook. When items wait for the project in the hook's `cwd`, it blocks the stop
/// and tells the agent to fetch them. It never takes items itself.
enum HookStop {
    static func output(openCount: Int) -> String? {
        guard openCount > 0 else { return nil }
        let reason = "\(openCount) new Point and Yap item(s) for this project. Call get_open_items (pointandyap MCP), do them, mark_done each."
        guard let data = try? JSONSerialization.data(withJSONObject: ["decision": "block", "reason": reason], options: [.withoutEscapingSlashes]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func run() {
        let input = FileHandle.standardInput.readDataToEndOfFile()
        let json = (try? JSONSerialization.jsonObject(with: input)) as? [String: Any]
        let cwd = json?["cwd"] as? String ?? FileManager.default.currentDirectoryPath
        let count = Items.openItems(limit: 100, take: false, agent: "hook", project: cwd).count
        if let line = output(openCount: count) { print(line) }
    }
}
