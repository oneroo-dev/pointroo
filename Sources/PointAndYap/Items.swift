import Foundation

/// The work queue: each recording is one item (an agent does everything said in it, then marks it done). Each item is open, in progress (an agent works on it), or done; the state lives in the session's state.json
/// and every change goes through one lock, so several agents can work at once.
struct Item {
    var id: String            // "<session>#<n>"
    var session: String
    var n: Int
    var title: String
    var body: String
    var crops: [URL]
    var status: String        // open, in_progress, done
    var at: Date?
    var by: String?
    var note: String?
    var project: String? = nil   // the project folder it was routed to (route.json)
    var routeHow: String? = nil  // how: said, screen, followup, only, picked
    var priority: String? = nil  // "urgent" when the user said urgent, asap or right now
    var commit: String? = nil    // the commit the agent made (mark_done)
    var branch: String? = nil    // the branch it is on (mark_done)
    var duplicateOf: String? = nil   // the id of the open item this repeats; it is not handed out on its own
    var alsoSaid: [String] = []      // repeats folded into this item, "id: said text"
    var said: String = ""            // everything the user said in the recording
    var firstElement: String? = nil  // the first pointed element, "role|name"
    var duration: Double = 0         // length of the recording in seconds
    var practice: Bool = false       // a practice recording: done by "you" at once, never handed out
}

struct ItemState: Codable {
    var source: String        // "session"; older builds wrote "timeline"
    var items: [String: Entry] = [:]
    struct Entry: Codable {
        var status: String; var by: String?; var at: Date; var note: String?
        var commit: String? = nil, branch: String? = nil
    }
}

/// What to do with items no project was found for.
enum Unrouted {
    case any      // hand them out (an explicit get_open_items)
    case never    // leave them (wait_for_next and the Stop hook)
}

enum Items {
    static let lease: TimeInterval = 2 * 3600   // an item in progress that no one finished comes back after two hours

    // MARK: Splitting a session

    static func items(in dir: URL, state: ItemState?) -> (source: String, items: [Item]) {
        let id = dir.lastPathComponent
        let source = "session"
        var out = sessionItems(dir)
        for i in out.indices {
            out[i].id = "\(id)#\(out[i].n)"
            out[i].session = id
            let route = Router.readRoute(dir)
            out[i].project = route?.path
            out[i].routeHow = route?.how
            if let follows = route?.follows { out[i].body = followUpLine(follows) + "\n\n" + out[i].body }
            if let e = state?.items[String(out[i].n)] {
                // "taken" is the older name of in_progress.
                let working = e.status == "taken" || e.status == "in_progress"
                out[i].status = working ? (Date().timeIntervalSince(e.at) > lease ? "open" : "in_progress") : e.status
                out[i].by = e.by; out[i].note = e.note; out[i].at = e.at
                out[i].commit = e.commit; out[i].branch = e.branch
            }
            if Practice.isPractice(dir) {
                out[i].practice = true
                out[i].status = "done"
                out[i].by = Practice.agent
                if out[i].note == nil { out[i].note = "Practice" }
            }
        }
        return (source, out)
    }

    /// The first line of a follow-up item: which item it follows, with the other agent's note marked as quoted text.
    static func followUpLine(_ id: String) -> String {
        let parts = id.split(separator: "#").map(String.init)
        var note = ""
        if parts.count == 2, !parts[0].contains("/"), !parts[0].contains("..") {
            note = readState(Paths.root.appendingPathComponent(parts[0]))?.items[parts[1]]?.note ?? ""
        }
        return note.isEmpty ? "Follow-up to \(id)."
            : "Follow-up to \(id). The agent that finished it wrote (quoted): \"\(note)\""
    }

    /// The recording as items: everything said, with [n] where the cursor was, and every click or rest of half
    /// a second or more (shorter rests are cursor travel; repeats on the same element count once).
    /// A spoken "next" splits it into several items (see Split); without one it is a single item.
    static func sessionItems(_ dir: URL) -> [Item] {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("events.json")),
              let events = try? JSONDecoder.iso.decode(SessionEvents.self, from: data) else { return [] }
        let words = (try? Data(contentsOf: dir.appendingPathComponent("transcript.json")))
            .flatMap { try? JSONDecoder().decode([Word].self, from: $0) } ?? []
        guard !words.isEmpty else { return [] }
        let parts = Split.parts(words: words, points: events.points)
        return parts.enumerated().map { offset, part in item(part, number: offset + 1, events: events, dir: dir) }
    }

    static func item(_ part: Split.Part, number: Int, events: SessionEvents, dir: URL) -> Item {
        var sents = Builder.sentences(part.words)
        _ = Builder.attach(part.points, to: &sents)
        var lines: [String] = []
        if let first = part.words.first, let last = part.words.last {
            lines.append("Said (\(Builder.clock(first.start)) to \(Builder.clock(last.end))): \""
                         + sents.map { Builder.marked($0, events.points) }.joined(separator: " ") + "\"")
        } else {
            lines.append("Said nothing, only pointed.")
        }
        lines += ["", "Pointed at:"]
        let pointed = sents.isEmpty ? part.points.map(\.index) : sents.flatMap(\.points)
        var crops: [URL] = [], last: String?
        for idx in pointed {
            let p = events.points[idx]
            guard p.kind == "click" || p.end - p.t >= 0.5 else { continue }
            let key = [p.element?.role, p.element?.title, p.element?.value, p.element?.identifier].map { $0 ?? "" }.joined(separator: "|")
            if key == last, p.kind != "click" { continue }
            last = key
            lines.append(pointLine(p, dir, &crops))
        }
        if lines.count == 3 { lines.removeLast(2) }
        let title = part.words.isEmpty ? "Pointed only" : part.words.prefix(12).map(\.text).joined(separator: " ")
        var item = Item(id: "", session: "", n: number, title: title, body: lines.joined(separator: "\n"), crops: crops, status: "open", at: nil)
        item.said = part.words.map(\.text).joined(separator: " ")
        item.priority = QueueRules.isUrgent(item.said) ? "urgent" : nil
        item.firstElement = QueueRules.elementIdentity(part.points)
        item.duration = events.duration
        return item
    }

    static func pointLine(_ p: PointEvent, _ dir: URL, _ crops: inout [URL]) -> String {
        var l = "- [\(p.index + 1)] \(p.kind) in \(p.app ?? "?")"
        if let w = p.window { l += ", window \"\(w)\"" }
        if let u = p.url { l += ", \(u)" }
        l += ": \(Builder.describe(p))"
        if let path = p.element?.path, !path.isEmpty { l += "; inside \(path.suffix(5).joined(separator: " > "))" }
        let crop = dir.appendingPathComponent(String(format: "crops/%02d.jpg", p.index + 1))
        if FileManager.default.fileExists(atPath: crop.path) { l += "; crop `\(crop.path)`"; crops.append(crop) }
        return l
    }

    // MARK: State

    static func stateURL(_ dir: URL) -> URL { dir.appendingPathComponent("state.json") }

    static func readState(_ dir: URL) -> ItemState? {
        (try? Data(contentsOf: stateURL(dir))).flatMap { try? JSONDecoder.iso.decode(ItemState.self, from: $0) }
    }

    /// False (and a line on stderr) when state.json could not be saved.
    @discardableResult
    static func writeState(_ s: ItemState, _ dir: URL) -> Bool {
        do {
            try JSONEncoder.pretty.encode(s).write(to: stateURL(dir), options: .atomic)
            return true
        } catch {
            FileHandle.standardError.write(Data("pointroo: could not save \(stateURL(dir).path): \(error.localizedDescription)\n".utf8))
            return false
        }
    }

    /// Runs `body` under ~/Pointroo/.lock (flock), so agents in separate processes never take the same item.
    static func locked<T>(_ body: () -> T) -> T {
        try? FileManager.default.createDirectory(at: Paths.root, withIntermediateDirectories: true)
        let fd = Darwin.open(Paths.root.deletingLastPathComponent().appendingPathComponent(".lock").path, O_CREAT | O_RDWR, 0o600)
        defer { if fd >= 0 { flock(fd, LOCK_UN); close(fd) } }
        if fd >= 0 { flock(fd, LOCK_EX) }
        return body()
    }

    /// Every session that is processed (has session.md), oldest first.
    static func sessionDirs() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: Paths.root, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.hasDirectoryPath && FileManager.default.fileExists(atPath: $0.appendingPathComponent("session.md").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Open items, urgent first and then oldest first; with `take`, they are marked in progress by `agent` before they are returned.
    /// With `project`, only that project's items (the path is the same or one is inside the other) and the ones not routed anywhere.
    /// An item that repeats an earlier open one (see QueueRules.fold) is not handed out; the original carries it in `alsoSaid`.
    static func openItems(limit: Int, take: Bool, agent: String, project: String? = nil,
                          unrouted: Unrouted = .any, since: Date? = nil) -> [Item] {
        locked {
            var states: [String: (dir: URL, state: ItemState?, source: String)] = [:]
            var everything: [Item] = []
            for dir in sessionDirs() {
                let state = readState(dir)
                let (source, items) = Self.items(in: dir, state: state)
                states[dir.lastPathComponent] = (dir, state, source)
                everything += items
            }
            let folded = QueueRules.fold(everything) { belongs($0, to: project, unrouted: unrouted, since: since) }
            let free = Array(QueueRules.ordered(folded.filter {
                $0.status == "open" && $0.duplicateOf == nil && belongs($0, to: project, unrouted: unrouted, since: since)
            }).prefix(limit))
            guard take else { return free }
            var failed: Set<String> = []
            for session in Set(free.map(\.session)) {
                guard let entry = states[session] else { continue }
                var state = entry.state ?? ItemState(source: entry.source)
                for item in free where item.session == session {
                    state.items[String(item.n)] = .init(status: "in_progress", by: agent, at: Date(), note: nil)
                }
                if !writeState(state, entry.dir) { failed.insert(session) }
            }
            return free.filter { !failed.contains($0.session) }.map { var item = $0; item.status = "in_progress"; item.by = agent; item.at = Date(); return item }
        }
    }

    /// With `since`, an item recorded before that time is only handed out when it was routed to the project on purpose
    /// (said, screen, follow-up or picked); a fallback route ("only") or an old recording is not.
    static func belongs(_ item: Item, to project: String?, unrouted: Unrouted = .any, since: Date? = nil) -> Bool {
        guard let project else { return true }
        guard let path = item.project else { return unrouted == .any }
        guard Router.related(path, project) else { return false }
        guard let since, !["said", "screen", "picked", "followup"].contains(item.routeHow ?? "") else { return true }
        return recordedAt(item.session).map { $0 > since } ?? false
    }

    /// The time in a session folder name (yyyy-MM-dd_HHmmss).
    static func recordedAt(_ session: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.date(from: session)
    }

    /// Sets items to done or open. Returns what changed and what was not found. `commit` and `branch` are stored with a done item.
    /// Marking an item done also closes the repeats folded into it (listed in `closedRepeats`).
    static func set(_ ids: [String], status: String, agent: String, note: String?,
                    commit: String? = nil, branch: String? = nil) -> (changed: [String], missing: [String], closedRepeats: [String]) {
        locked {
            var changed: [String] = [], missing: [String] = [], closedRepeats: [String] = []
            var repeatNotes: [String: String] = [:]
            if status == "done" {
                for item in all() {
                    if let original = item.duplicateOf, ids.contains(original), !ids.contains(item.id) {
                        repeatNotes[item.id] = "Same as \(original), done with it." + (note.map { " \($0)" } ?? "")
                    }
                }
            }
            let bySession = Dictionary(grouping: ids + repeatNotes.keys.sorted()) { String($0.split(separator: "#").first ?? "") }
            for (session, list) in bySession {
                let dir = Paths.root.appendingPathComponent(session)
                guard !session.isEmpty, !session.contains("/"), !session.contains(".."),
                      FileManager.default.fileExists(atPath: dir.appendingPathComponent("session.md").path) else { missing += list; continue }
                var st = readState(dir)
                let (source, items) = Self.items(in: dir, state: st)
                if st == nil { st = ItemState(source: source) }
                var sessionChanged: [String] = [], closed: [String] = []
                for id in list {
                    guard let item = items.first(where: { $0.id == id }) else { missing.append(id); continue }
                    if status == "in_progress", item.status == "done" || (item.status == "in_progress" && item.by != agent) {
                        missing.append("\(id) (\(item.status == "done" ? "done" : "in progress by \(item.by ?? "another agent")"))"); continue
                    }
                    let isRepeat = repeatNotes[id] != nil
                    st!.items[String(item.n)] = .init(status: status, by: agent, at: Date(), note: repeatNotes[id] ?? note,
                                                      commit: status == "done" && !isRepeat ? commit : nil,
                                                      branch: status == "done" && !isRepeat ? branch : nil)
                    sessionChanged.append(id)
                    if isRepeat { closed.append(id) }
                }
                let requested = sessionChanged.filter { repeatNotes[$0] == nil }
                if writeState(st!, dir) { changed += requested; closedRepeats += closed }
                else { missing += requested.map { "\($0) (could not save state)" } }
            }
            return (changed, missing, closedRepeats)
        }
    }

    /// Every item, oldest first, for an overview. A repeat of an earlier open item shows with `duplicateOf`.
    static func all() -> [Item] { QueueRules.fold(sessionDirs().flatMap { items(in: $0, state: readState($0)).items }) }
}
