import AppKit
import Foundation

/// `Pointroo --mcp`: a local MCP server over stdio (newline-delimited JSON-RPC), no auth. It only reads ~/Pointroo/sessions.
enum MCPServer {
    static let protocolVersion = "2025-06-18"
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    /// `Pointroo --mcp` without the app running: one connection on stdin and stdout.
    static func run() {
        setvbuf(stdout, nil, _IOLBF, 0)
        let connection = MCPConnection(cwd: FileManager.default.currentDirectoryPath, manageLiveSession: true)
        while let line = readLine(strippingNewline: true) {
            if let reply = connection.handle(line: line) { print(reply) }
        }
        connection.close()
    }

    /// One stdio-style connection for the folder the process runs in (used by tests).
    nonisolated(unsafe) static let stdio = MCPConnection(cwd: FileManager.default.currentDirectoryPath)

    static func call(_ name: String, _ arguments: [String: Any]) -> [String: Any] { stdio.call(name, arguments) }

    static let instructions = """
    Pointroo is the user's queue of things to fix: they point at things on their screen and talk, and every \
    recording becomes an item (what they said, the elements under the cursor, cropped screenshots). Work through the queue: get_open_items takes \
    the open items for you, do each one, then mark_done with its id and a one-line note; release_items gives back what \
    you could not do. Done items are never handed out again. get_session reads a whole recording. Items are routed to \
    projects: you get the ones for the folder you run in, plus the ones not routed anywhere (scope "all" shows every project's). \
    To listen for new items without the user pasting anything, call wait_for_next: it waits until an item for this project \
    arrives and returns it like get_open_items; it returns after up to 50 s with nothing new, so call it again in a loop: \
    do the item, mark_done, then call wait_for_next again. Pass commit and branch to mark_done when you made one. \
    Urgent items come first. When you need an answer from the user, call ask_user; if it \
    says there is no answer yet, carry on and call it again with the question_id it gave you.
    """

    static let tools: [[String: Any]] = [
        ["name": "get_open_items",
         "description": "The open items of the user's Pointroo queue, urgent ones first and then oldest first, each with its id, what they said, the elements they pointed at and its crop (red ring = cursor, yellow box = element). By default they are marked in progress by you, so no other agent gets them; finish each with mark_done.",
         "inputSchema": ["type": "object", "properties": [
            "limit": ["type": "integer", "description": "How many, default 5"],
            "take": ["type": "boolean", "description": "Mark them in progress by you, default true; false only looks"],
            "images": ["type": "boolean", "description": "Include the crops as images, default true"],
            "scope": ["type": "string", "description": "Default: only this project's items (the folder you run in) and items not routed anywhere. \"all\" returns every project's"]]]],
        ["name": "wait_for_next",
         "description": "Listen mode: wait until a new open item for this project arrives (it is marked in progress by you and returned like get_open_items), or until the timeout (up to 50 s by default, 55 s at most; call it again in a loop). After you finish the item and mark_done, call wait_for_next again to keep listening. On timeout it says nothing new yet; just call it again.",
         "inputSchema": ["type": "object", "properties": [
            "timeout_seconds": ["type": "integer", "description": "How long to wait, default 50, max 55"],
            "images": ["type": "boolean", "description": "Include the crops as images, default true"]]]],
        ["name": "ask_user",
         "description": "Ask the user a question and wait for the answer (up to 50 s by default, 55 s at most). Use it when you cannot go on without them. If it says there is no answer yet, do other work and call it again with the question_id it gave you. If Pointroo is not running or cannot show questions, it says so: ask in chat instead.",
         "inputSchema": ["type": "object", "properties": [
            "question": ["type": "string", "description": "The question, short and plain. Required unless you pass question_id"],
            "choices": ["type": "array", "items": ["type": "string"], "description": "Up to 4 answers to pick from (optional)"],
            "question_id": ["type": "string", "description": "Only wait for the answer to an earlier question; asks nothing new"],
            "timeout_seconds": ["type": "number", "description": "How long to wait, default 50, max 55"]]]],
        ["name": "mark_done",
         "description": "Mark items done once the change is made, so they are never handed out again.",
         "inputSchema": ["type": "object", "required": ["ids"], "properties": [
            "ids": ["type": "array", "items": ["type": "string"], "description": "Item ids, e.g. 2026-10-17_164301#2"],
            "note": ["type": "string", "description": "One line: what you changed (file, commit)"],
            "commit": ["type": "string", "description": "The commit you made, 7 to 40 hex characters (optional; pass it when you made one)"],
            "branch": ["type": "string", "description": "The branch it is on, no spaces, at most 200 characters (optional; pass it when you made one)"]]]],
        ["name": "start_items",
         "description": "Mark specific open items in progress by you (after looking with take false), so no other agent does them. Refuses items done or in progress by another agent.",
         "inputSchema": ["type": "object", "required": ["ids"], "properties": [
            "ids": ["type": "array", "items": ["type": "string"]]]]],
        ["name": "list_items",
         "description": "Every item with its state: open, in progress (by which agent, since when) or done (by whom, with the note). No images.",
         "inputSchema": ["type": "object", "properties": [
            "status": ["type": "string", "description": "open, in_progress or done; default all except done"]]]],
        ["name": "release_items",
         "description": "Give items you have in progress back to the queue (you could not do them, or they need the user); they are handed out again.",
         "inputSchema": ["type": "object", "required": ["ids"], "properties": [
            "ids": ["type": "array", "items": ["type": "string"]],
            "note": ["type": "string", "description": "Why, for the user or the next agent"]]]],
        ["name": "list_sessions",
         "description": "List recent recordings, newest first: id, time, length, number of points, first words.",
         "inputSchema": ["type": "object", "properties": ["limit": ["type": "integer", "description": "How many, default 10"]]]],
        ["name": "get_session",
         "description": "One recording: the aligned timeline (what the user said, with [n] where they pointed and the element there), the folder, and the cropped screenshot of each point as images (red ring = cursor, yellow box = element).",
         "inputSchema": ["type": "object", "properties": [
            "id": ["type": "string", "description": "Session id from list_sessions, default latest"],
            "images": ["type": "boolean", "description": "Include the crops as images, default true"]]]],
        ["name": "get_frame",
         "description": "A full screenshot from a session (frames/NNN.jpg), downscaled, for context beyond a crop.",
         "inputSchema": ["type": "object", "properties": [
            "id": ["type": "string", "description": "Session id, default latest"],
            "frame": ["type": "string", "description": "Frame file, e.g. frames/003.jpg; default the first"]]]],
    ]

    static func dirs() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: Paths.root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.hasDirectoryPath && FileManager.default.fileExists(atPath: $0.appendingPathComponent("events.json").path) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func dir(_ id: String?) -> URL? {
        guard let id, !id.isEmpty, id != "latest" else { return dirs().first }
        let d = Paths.root.appendingPathComponent(id)
        // Only a plain session folder name.
        guard !id.contains("/"), !id.contains(".."), FileManager.default.fileExists(atPath: d.path) else { return nil }
        return d
    }

    static func listSessions(limit: Int) -> String {
        let rows = dirs().prefix(max(1, min(limit, 50))).map { d -> String in
            var line = "- \(d.lastPathComponent)"
            if let data = try? Data(contentsOf: d.appendingPathComponent("events.json")),
               let e = try? JSONDecoder.iso.decode(SessionEvents.self, from: data) {
                line += ": \(Int(e.duration.rounded())) s, \(e.points.count) points"
            }
            if let w = try? Data(contentsOf: d.appendingPathComponent("transcript.json")),
               let words = try? JSONDecoder().decode([Word].self, from: w), !words.isEmpty {
                line += ", \"\(words.prefix(12).map(\.text).joined(separator: " "))…\""
            }
            if let i = Items.items(in: d, state: Items.readState(d)).items.first {
                line += ", \(i.status.replacingOccurrences(of: "_", with: " "))\(i.by.map { " by \($0)" } ?? "")"
            }
            return line
        }
        return rows.isEmpty ? "No recordings yet." : rows.joined(separator: "\n")
    }

    static func getSession(_ id: String?, images: Bool) -> [String: Any] {
        guard let d = dir(id) else { return error("no such session") }
        let tl = try? String(contentsOf: d.appendingPathComponent("session.md"), encoding: .utf8)
        var body = "Recording \(d.lastPathComponent), folder \(d.path)\n\n"
        body += tl ?? "This session has not been processed yet."
        for item in Items.items(in: d, state: Items.readState(d)).items {
            if let line = QueueRules.commitLine(item) { body += "\n\nItem \(item.id) was finished with \(line)." }
        }
        body += "\n\nThe work items of this session come from get_open_items; finish each with mark_done."
        var content: [[String: Any]] = [["type": "text", "text": body]]
        if images {
            let crops = ((try? FileManager.default.contentsOfDirectory(atPath: d.appendingPathComponent("crops").path)) ?? [])
                .filter { $0.hasSuffix(".jpg") }.sorted().prefix(12)
            for c in crops {
                guard let data = try? Data(contentsOf: d.appendingPathComponent("crops/\(c)")) else { continue }
                let n = Int(c.dropLast(4)) ?? 0
                content.append(["type": "text", "text": "Crop for point [\(n)]: \(d.path)/crops/\(c)"])
                content.append(["type": "image", "data": data.base64EncodedString(), "mimeType": "image/jpeg"])
            }
        }
        return ["content": content]
    }

    static func getFrame(_ id: String?, frame: String?) -> [String: Any] {
        guard let d = dir(id) else { return error("no such session") }
        let name = frame ?? ((try? FileManager.default.contentsOfDirectory(atPath: d.appendingPathComponent("frames").path))?
            .filter { $0.hasSuffix(".jpg") }.sorted().first.map { "frames/\($0)" } ?? "")
        guard name.hasPrefix("frames/"), !name.contains(".."),
              let img = NSImage(contentsOf: d.appendingPathComponent(name))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return error("no such frame") }
        let w = min(1600, img.width), h = img.height * w / img.width
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return error("could not read the frame") }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let out = ctx.makeImage(),
              let data = NSBitmapImageRep(cgImage: out).representation(using: .jpeg, properties: [.compressionFactor: 0.75])
        else { return error("could not read the frame") }
        return ["content": [["type": "text", "text": "\(d.path)/\(name)"],
                            ["type": "image", "data": data.base64EncodedString(), "mimeType": "image/jpeg"]]]
    }

    /// The Claude desktop app cancels a stdio tool call after about 60 s, so one wait stays under that.
    static let defaultWait = 50
    static func waitTimeout(_ requested: Int) -> Int { max(0, min(requested, 55)) }

    static func handOut(_ items: [Item], take: Bool, images: Bool) -> [String: Any] {
        var content: [[String: Any]] = [["type": "text", "text":
            "\(items.count) open item\(items.count == 1 ? "" : "s")\(take ? ", now in progress by you" : ""). Fix each, then call mark_done with its id right away: an item you leave unmarked stays open for the user and comes back to another agent in two hours."]]
        for i in items {
            var t = "### Item \(i.id)\(i.priority == "urgent" ? " (URGENT, the user said so)" : "")\n\n\(i.body)\n\nWhen this is fixed, call mark_done with id \"\(i.id)\" (the user sees it as done)."
            for repeated in i.alsoSaid {
                t += "\n\nAlso said (the same thing again in a later recording, folded into this item; marking this one done closes it too) \(repeated)"
            }
            if let note = i.note, !note.isEmpty { t += "\n\nNote from \(i.by ?? "an agent") when it gave this back: \(note)" }
            content.append(["type": "text", "text": t])
            if images {
                for c in i.crops.prefix(4) {
                    guard let data = try? Data(contentsOf: c) else { continue }
                    content.append(["type": "image", "data": data.base64EncodedString(), "mimeType": "image/jpeg"])
                }
            }
        }
        return ["content": content]
    }

    static func listItems(_ status: String?) -> [String: Any] {
        let all = Items.all()
        let shown = status.map { st in all.filter { $0.status == st } } ?? all.filter { $0.status != "done" }
        guard !shown.isEmpty else { return text(status == nil ? "Nothing open or in progress." : "No items \(status!).") }
        let f = DateFormatter(); f.dateFormat = "d MMM HH:mm"
        let rows = shown.map { i -> String in
            var l = "- \(i.id) [\(i.status.replacingOccurrences(of: "_", with: " "))"
            if let by = i.by, i.status != "open" { l += " by \(by)" }
            if let at = i.at, i.status != "open" { l += " since \(f.string(from: at))" }
            l += "]"
            if i.priority == "urgent" { l += " URGENT" }
            if i.practice { l += " Practice" }
            if let original = i.duplicateOf { l += " (duplicate of \(original), not handed out on its own)" }
            if let project = i.project { l += " (project \(Projects.name(for: project)))" }
            l += " \"\(i.title)…\""
            if let n = i.note, !n.isEmpty { l += ", note: \(n)" }
            if let line = QueueRules.commitLine(i) { l += ", \(line)" }
            return l
        }
        let c = (all.filter { $0.status == "open" }.count, all.filter { $0.status == "in_progress" }.count, all.filter { $0.status == "done" }.count)
        return text("\(c.0) open, \(c.1) in progress, \(c.2) done.\n" + rows.joined(separator: "\n"))
    }

    static func text(_ s: String) -> [String: Any] { ["content": [["type": "text", "text": s]]] }
    static func error(_ s: String) -> [String: Any] { ["content": [["type": "text", "text": s]], "isError": true] }
}

/// One client of the MCP server: its own agent name, folder and start time. Over stdio there is one; in the app there is one per bridge.
final class MCPConnection {
    /// The client's name from initialize with the folder in brackets; recorded on the items it takes and finishes.
    private(set) var agent = "agent"
    /// When the client started: wait_for_next leaves older recordings to the user (unless routed to this project on purpose).
    let startedAt: Date
    /// The project of this session.
    let cwd: String
    /// False once the client has gone away (a socket); wait_for_next checks it before every take.
    let isOpen: () -> Bool
    /// Only the stdio and in-process path registers a live session; in the app the bridge does it.
    private let manageLiveSession: Bool

    init(cwd: String, startedAt: Date = Date(), manageLiveSession: Bool = false, isOpen: @escaping () -> Bool = { true }) {
        self.cwd = cwd
        self.startedAt = startedAt
        self.manageLiveSession = manageLiveSession
        self.isOpen = isOpen
    }

    func close() { if manageLiveSession { LiveSessions.unregister() } }

    /// One JSON-RPC line in, the reply line out (nil for notifications and lines that are not requests).
    func handle(line: String) -> String? {
        guard !line.isEmpty, let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        guard let id = message["id"] else { return nil }
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            var client = "agent"
            if let info = params["clientInfo"] as? [String: Any], let name = info["name"] as? String, !name.isEmpty { client = name }
            if manageLiveSession { LiveSessions.register(cwd: cwd, agent: client) }
            agent = "\(client) (\(URL(fileURLWithPath: cwd).lastPathComponent))"
            let asked = params["protocolVersion"] as? String
            return reply(id, ["protocolVersion": asked ?? MCPServer.protocolVersion,
                              "capabilities": ["tools": [:]],
                              "serverInfo": ["name": "pointroo", "title": "Pointroo", "version": MCPServer.version],
                              "instructions": MCPServer.instructions])
        case "ping": return reply(id, [:])
        case "tools/list": return reply(id, ["tools": MCPServer.tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            if manageLiveSession { LiveSessions.touch() }
            return reply(id, call(name, arguments))
        default:
            return encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "method not found: \(method)"]])
        }
    }

    func call(_ name: String, _ a: [String: Any]) -> [String: Any] {
        switch name {
        case "get_open_items":
            return openItems(limit: a["limit"] as? Int ?? 5, take: a["take"] as? Bool ?? true, images: a["images"] as? Bool ?? true,
                             project: (a["scope"] as? String) == "all" ? nil : cwd)
        case "wait_for_next":
            let seconds = (a["timeout_seconds"] as? Int) ?? (a["timeout_seconds"] as? Double).map { Int($0) } ?? MCPServer.defaultWait
            return waitForNext(timeout: MCPServer.waitTimeout(seconds), images: a["images"] as? Bool ?? true)
        case "ask_user": return askUser(a)
        case "mark_done": return setItems(a["ids"], status: "done", note: a["note"] as? String,
                                          commit: a["commit"], branch: a["branch"])
        case "start_items": return setItems(a["ids"], status: "in_progress", note: nil)
        case "list_items": return MCPServer.listItems(a["status"] as? String)
        case "release_items": return setItems(a["ids"], status: "open", note: a["note"] as? String)
        case "list_sessions": return MCPServer.text(MCPServer.listSessions(limit: a["limit"] as? Int ?? 10))
        case "get_session": return MCPServer.getSession(a["id"] as? String, images: a["images"] as? Bool ?? true)
        case "get_frame": return MCPServer.getFrame(a["id"] as? String, frame: a["frame"] as? String)
        default: return MCPServer.error("unknown tool \(name)")
        }
    }

    /// Waits for an item for this project. The connection is checked before every take, so a client that has gone away never takes one.
    func waitForNext(timeout: Int, images: Bool) -> [String: Any] {
        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        var polls = 0
        while true {
            guard isOpen() else { return MCPServer.text("The connection is closed.") }
            let items = Items.openItems(limit: 5, take: true, agent: agent, project: cwd, unrouted: .never, since: startedAt)
            if !items.isEmpty { return MCPServer.handOut(items, take: true, images: images) }
            if Date() >= deadline { break }
            polls += 1
            if polls % 15 == 0, manageLiveSession { LiveSessions.touch() }
            Thread.sleep(forTimeInterval: 1)
        }
        return MCPServer.text("Nothing new yet. Call wait_for_next again to keep listening.")
    }

    func openItems(limit: Int, take: Bool, images: Bool, project: String? = nil) -> [String: Any] {
        let items = Items.openItems(limit: max(1, min(limit, 20)), take: take, agent: agent, project: project)
        guard !items.isEmpty else {
            let working = Items.all().filter { $0.status == "in_progress" }
            if working.isEmpty { return MCPServer.text("No open items. Everything the user pointed at is done.") }
            let who = Set(working.compactMap(\.by)).sorted().joined(separator: ", ")
            return MCPServer.text("No open items. \(working.count) in progress (\(who)); nothing else to do.")
        }
        return MCPServer.handOut(items, take: take, images: images)
    }

    func setItems(_ raw: Any?, status: String, note: String?, commit: Any? = nil, branch: Any? = nil) -> [String: Any] {
        let ids = (raw as? [String]) ?? (raw as? String).map { [$0] } ?? []
        guard !ids.isEmpty else { return MCPServer.error("ids missing") }
        if let commit {
            guard let text = commit as? String, QueueRules.isValidCommit(text) else {
                return MCPServer.error("commit must be 7 to 40 hex characters (the commit id). Nothing was changed.")
            }
        }
        if let branch {
            guard let text = branch as? String, QueueRules.isValidBranch(text) else {
                return MCPServer.error("branch must have no spaces or new lines and be at most 200 characters. Nothing was changed.")
            }
        }
        let r = Items.set(ids, status: status, agent: agent, note: note, commit: commit as? String, branch: branch as? String)
        let verb = ["done": "Done", "in_progress": "In progress by you"][status] ?? "Back in the queue"
        var s = r.changed.isEmpty ? "" : "\(verb): \(r.changed.joined(separator: ", "))."
        if !r.closedRepeats.isEmpty { s += " Also closed (the same thing said again): \(r.closedRepeats.joined(separator: ", "))." }
        if !r.missing.isEmpty { s += (s.isEmpty ? "" : " ") + "Not changed: \(r.missing.joined(separator: ", "))." }
        return r.changed.isEmpty ? MCPServer.error(s) : MCPServer.text(s)
    }

    private func reply(_ id: Any, _ result: [String: Any]) -> String? { encode(["jsonrpc": "2.0", "id": id, "result": result]) }

    private func encode(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
