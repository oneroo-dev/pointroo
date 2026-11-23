import AppKit
import Foundation

/// The line between the web screens (the kit app in a web view) and the app. Plain request in, plain reply out, no web view needed.
///
/// The page sends one JSON message per call: `window.webkit.messageHandlers.pointroo.postMessage({id, method, params})`.
///   id      a number or a string the page picks. It comes back unchanged in the reply.
///   method  one name from the table below.
///   params  an object (may be left out).
///
/// The app answers by running `window.pointroo.reply(<id>, <json>)` in the page, where json is
///   `{"result": ...}` when it worked, or `{"error": {"code": "...", "message": "..."}}` when it did not.
/// The app can also tell the page about something with `window.pointroo.emit(<name>, <json data>)`.
///
/// Events the app sends once WebHost.startEvents runs (about once a second, only when something changed; the first of each is sent at start):
///   items.changed      {count, open, inProgress}   an item came, went, or changed status, note or project
///   questions.changed  {count}                     the set of unanswered agent questions changed
///   recording.changed  {phase, pointCount}         phase is "idle", "recording" or "processing"
///   status.changed     {mcpRunning, mcpPort, mcpText, sessions, agents, microphone, screenRecording, accessibility}
///                      the same object status.get returns inside `status`; sent when any part of it changed
///
/// Error codes: bad_request (not valid JSON, or no method), unknown_method, bad_params, not_found, not_available, refused.
///
/// Methods
///   items.list      params {status?: "open" | "in_progress" | "done" | "trashed", project?: string, maxAgeHours?: number, groupBy?: "project"}
///                   status    no status = every item except the trashed ones; "trashed" gives only the trashed ones
///                   project   a project's name or folder path; "none" means items with no project; error not_found when unknown
///                   maxAgeHours  a number above 0: only items made within that many hours (uses the item's `at` date; an item with no date is left out)
///                   groupBy   only "project" is allowed
///                   result {items: [Item]}   in the order the queue gives them (unchanged)
///                   with groupBy: result {groups: [{project: {name, path} or null, items: [Item]}]}
///                   groups follow projects.list order (live projects first, then the rest by name), then folders that are not known
///                   projects, and the group with no project (project null) last; inside a group the newest item comes first
///                   (items with no date last, ties keep the queue order). Groups with no items are left out.
///   projects.list   no params
///                   result {projects: [{name, path, aliases: [string], live: bool, agents: [string], key?: 1...9, open, inProgress}]}
///                   live projects come first (in picker order), then the others by name ignoring case. `key` is the picker's number key,
///                   given to the first nine live projects only. `open` and `inProgress` count the items routed to that folder.
///   items.get       params {id: string}
///                   result {item: Item}   error not_found when there is no such item
///   items.reroute   params {id: string, project: string}   (project is a project's name or folder path, as in Projects.known())
///                   result {moved: true}
///                   error not_found (no such item, or no such project), refused (the item is done), not_available (could not save), bad_params
///   items.done      params {id: string, note?: string}   the same as the Done button: status done, by "user"
///                   result {done: true}   error not_found, not_available (could not save), bad_params (no id, or note is not text)
///   items.reopen    params {id: string}   back to open (works for done and trashed items; an item in progress goes back to open too)
///                   result {reopened: true}   error not_found, not_available, bad_params
///   items.trash     params {id: string}   hides the item from the queue; nothing is deleted. Its status becomes "trashed": agents are
///                   never given it, and items.list leaves it out unless status "trashed" is asked. items.reopen brings it back.
///                   result {trashed: true}   error not_found, not_available, bad_params
///   items.unroute   params {id: string}   undoes a send: removes the route of the item's recording (route.json is per recording, so
///                   every item of that recording is then unrouted). A recording that has no route answers unrouted too.
///                   result {unrouted: true}   error not_found, refused (an agent took the item or it is done), not_available, bad_params
///   clipboard.copy  params {text: string}   puts the text on the clipboard
///                   result {copied: true}   error bad_params when text is not a non-empty string
///   window.startDrag no params   the page calls this from a mousedown on its own drag area; the window then follows the mouse
///                   result {dragging: true}   error not_available when the app gave no way to drag
///   questions.list  no params
///                   result {questions: [Question]}   unanswered questions from agents, oldest first
///   questions.answer params {id: string, text: string}
///                   result {answered: true}   error not_found when the question is unknown or already answered, bad_params when id or text is missing
///   settings.get    params {key?: string}
///                   result {key, value} for one key, or {values: {key: value}} for all allowed keys
///   settings.set    params {key: string, value: bool | string}
///                   result {key, value}   error refused when the key is not in the allowed list, bad_params when the value has the wrong kind
///   status.get      no params
///                   result {status: {mcpRunning: bool (the listener has a port), mcpPort: number (the bound port, else the configured one),
///                   mcpText: string (the listener's status line), sessions: number (running agent sessions), agents: [string] (distinct, sorted),
///                   microphone: bool, screenRecording: bool, accessibility: bool}}
///   permissions.ask params {which: "microphone" | "screenRecording" | "accessibility"}
///                   result {asked: true}   error bad_params when which is missing or unknown, not_available when the app gave no way to ask
///
/// Item: {id, session, n, title, body, crops: [path], status, alsoSaid: [string], at?: ISO date, by?, note?, project?, routeHow?,
///        priority?, commit?, branch?, duplicateOf?, said?, firstElement?, duration?}
///   A key marked ? is left out when it has no value (never null).
///   alsoSaid      repeats folded into this item, "id: said text" (empty array when none)
///   priority      "urgent" when the user said urgent, asap or right now
///   commit        the commit the agent made when it marked the item done
///   branch        the branch that commit is on
///   duplicateOf   the id of the open item this one repeats
///   said          everything the user said in the recording
///   firstElement  the first pointed element, "role|name"
///   duration      length of the recording in seconds
///
/// An Item also has cropURLs: [string] (one pointroo-image:// address per crop, same order as crops) and afterURL? (the address of
/// after/01.jpg, only when that file exists). A page shows a picture by using these in an img tag. The scheme is
/// `pointroo-image://session/<session id>/<relative path>`; only files under crops, frames and after of one session are served
/// (see WebImages).
///
/// Question: {id, project, agent, text, choices: [string], asked: seconds since 1970}
///   A key with no value is left out (an empty choices list is an empty array).
///
/// Settings keys: sounds, doubleControl, escCancels, redactSecrets, connectAgents, showNoSpeech, holdToTalk, listenAfterDone, kitWindow (all bool);
/// locale (string, one of the ids in Prefs.languages).
final class WebBridge {
    struct Request {
        var id: Any
        var method: String
        var params: [String: Any]
    }

    struct Failure: Error {
        var code: String
        var message: String
    }

    typealias Handler = (WebBridge, [String: Any]) throws -> Any

    /// A settings key the page may read and write, with its kind and what it is when never set.
    enum SettingKind {
        case flag(defaultValue: Bool)
        case choice(allowed: [String], defaultValue: String)
    }

    static let allowedSettings: [(key: String, kind: SettingKind)] = [
        ("sounds", .flag(defaultValue: true)),
        ("doubleControl", .flag(defaultValue: true)),
        ("escCancels", .flag(defaultValue: true)),
        ("redactSecrets", .flag(defaultValue: true)),
        ("connectAgents", .flag(defaultValue: false)),
        ("showNoSpeech", .flag(defaultValue: false)),
        ("holdToTalk", .flag(defaultValue: false)),
        ("listenAfterDone", .flag(defaultValue: false)),
        ("kitWindow", .flag(defaultValue: true)),
        ("locale", .choice(allowed: Prefs.languages.map(\.id), defaultValue: "")),
    ]

    /// The whitelist. A method that is not here is an error.
    static let methods: [String: Handler] = [
        "items.list": { bridge, params in try bridge.itemsList(params) },
        "projects.list": { bridge, params in try bridge.projectsList(params) },
        "items.get": { bridge, params in try bridge.itemsGet(params) },
        "items.reroute": { bridge, params in try bridge.itemsReroute(params) },
        "items.done": { bridge, params in try bridge.itemsChangeStatus(params, status: "done", key: "done") },
        "items.reopen": { bridge, params in try bridge.itemsChangeStatus(params, status: "open", key: "reopened") },
        "items.trash": { bridge, params in try bridge.itemsChangeStatus(params, status: "trashed", key: "trashed") },
        "items.unroute": { bridge, params in try bridge.itemsUnroute(params) },
        "clipboard.copy": { bridge, params in try bridge.clipboardCopy(params) },
        "window.startDrag": { bridge, params in try bridge.windowStartDrag(params) },
        "questions.list": { bridge, params in try bridge.questionsList(params) },
        "questions.answer": { bridge, params in try bridge.questionsAnswer(params) },
        "settings.get": { bridge, params in try bridge.settingsGet(params) },
        "settings.set": { bridge, params in try bridge.settingsSet(params) },
        "status.get": { bridge, params in try bridge.statusGet(params) },
        "permissions.ask": { bridge, params in try bridge.permissionsAsk(params) },
    ]

    private let defaults: UserDefaults
    private let loadItems: () -> [Item]
    private let findProject: (String) -> Project?
    private let reroute: (String, Project) -> Items.RerouteResult
    private let loadProjects: () -> [Project]
    private let loadLive: () -> [LiveSession]
    private let loadStatus: () -> AppStatus
    private let askPermission: ((String) -> Void)?
    private let changeStatus: (String, String, String?) -> StatusChange
    private let unroute: (String) -> Items.UnrouteResult
    private let writeClipboard: (String) -> Void
    private let startDrag: (() -> Void)?

    /// What changing one item's status did.
    enum StatusChange: Equatable {
        case changed
        case missing
        case saveFailed
    }

    /// The real status change: Items.set for one item, by "user" (the same call the Done button makes).
    static func changeItemStatus(id: String, status: String, note: String?) -> StatusChange {
        let result = Items.set([id], status: status, agent: "user", note: note)
        if !result.changed.isEmpty { return .changed }
        return result.missing.contains { $0.contains("could not save") } ? .saveFailed : .missing
    }

    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// `loadStatus` gives the MCP and permission state for status.get (the default reads the real values).
    /// `askPermission` is called with "microphone", "screenRecording" or "accessibility"; when it is nil, permissions.ask answers not_available.
    /// `findProject` turns the page's text (a name or a folder path) into a known project. `reroute` moves the item.
    /// `loadProjects` and `loadLive` give the projects and the running agent sessions for projects.list and the grouping.
    /// The defaults use the real project list and Items.reroute (the same call AppState.reroute makes, without its banner).
    /// `changeStatus` (id, new status, note) serves items.done, items.reopen and items.trash. `unroute` serves items.unroute.
    /// `startDrag` serves window.startDrag; when it is nil, that method answers not_available.
    /// `writeClipboard` serves clipboard.copy. The defaults are the real Items.set, Items.unroute and the general pasteboard.
    init(defaults: UserDefaults = .standard,
         loadItems: @escaping () -> [Item] = { Items.all() },
         findProject: @escaping (String) -> Project? = { WebBridge.knownProject($0) },
         reroute: @escaping (String, Project) -> Items.RerouteResult = { Items.reroute(id: $0, to: $1) },
         loadProjects: @escaping () -> [Project] = { Projects.load() },
         loadLive: @escaping () -> [LiveSession] = { LiveSessions.all() },
         loadStatus: @escaping () -> AppStatus = { AppStatus.readNow() },
         askPermission: ((String) -> Void)? = nil,
         changeStatus: @escaping (String, String, String?) -> StatusChange = { WebBridge.changeItemStatus(id: $0, status: $1, note: $2) },
         unroute: @escaping (String) -> Items.UnrouteResult = { Items.unroute(id: $0) },
         writeClipboard: @escaping (String) -> Void = { WebBridge.copyToClipboard($0) },
         startDrag: (() -> Void)? = nil) {
        self.defaults = defaults
        self.loadItems = loadItems
        self.findProject = findProject
        self.reroute = reroute
        self.loadProjects = loadProjects
        self.loadLive = loadLive
        self.loadStatus = loadStatus
        self.askPermission = askPermission
        self.changeStatus = changeStatus
        self.unroute = unroute
        self.writeClipboard = writeClipboard
        self.startDrag = startDrag
    }

    /// A known project whose folder is this path, or whose name is this text (ignoring case).
    static func knownProject(_ text: String) -> Project? {
        let projects = Projects.known()
        return projects.first { Router.samePath($0.path, text) }
            ?? projects.first { $0.name.caseInsensitiveCompare(text) == .orderedSame }
    }

    /// Takes what the page posted (a dictionary or a JSON string) and returns the script to run in the page.
    func handle(message: Any) -> String {
        guard let request = Self.decode(message) else {
            return Self.replyScript(id: NSNull(), outcome: .failure(Failure(code: "bad_request", message: "Not a request with an id and a method.")))
        }
        guard let handler = Self.methods[request.method] else {
            return Self.replyScript(id: request.id, outcome: .failure(Failure(code: "unknown_method", message: "Unknown method \(request.method).")))
        }
        do {
            return Self.replyScript(id: request.id, outcome: .success(try handler(self, request.params)))
        } catch let failure as Failure {
            return Self.replyScript(id: request.id, outcome: .failure(failure))
        } catch {
            return Self.replyScript(id: request.id, outcome: .failure(Failure(code: "bad_request", message: "\(error)")))
        }
    }

    static func decode(_ message: Any) -> Request? {
        var object: [String: Any]?
        if let dictionary = message as? [String: Any] {
            object = dictionary
        } else if let text = message as? String, let data = text.data(using: .utf8) {
            object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        guard let object, let method = object["method"] as? String, !method.isEmpty else { return nil }
        guard let id = object["id"], id is String || id is NSNumber else { return nil }
        return Request(id: id, method: method, params: object["params"] as? [String: Any] ?? [:])
    }

    static func replyScript(id: Any, outcome: Result<Any, Failure>) -> String {
        let payload: [String: Any]
        switch outcome {
        case .success(let value): payload = ["result": value]
        case .failure(let failure): payload = ["error": ["code": failure.code, "message": failure.message]]
        }
        return "window.pointroo.reply(\(json(id)), \(json(payload)))"
    }

    static func emitScript(name: String, data: Any) -> String {
        "window.pointroo.emit(\(json(name)), \(json(data)))"
    }

    /// JSON text that is safe to put inside a script: made by JSONSerialization, never by joining strings, and with the
    /// characters that can end a script or a JavaScript string early written as escapes.
    static func json(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value]),
              let wrapped = String(data: data, encoding: .utf8) else { return "null" }
        let text = String(wrapped.dropFirst().dropLast())
        return text
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    private func itemsList(_ params: [String: Any]) throws -> Any {
        var items = loadItems()
        if let status = params["status"] {
            guard let wanted = status as? String, ["open", "in_progress", "done", "trashed"].contains(wanted) else {
                throw Failure(code: "bad_params", message: "status must be open, in_progress, done or trashed.")
            }
            items = items.filter { $0.status == wanted }
        } else {
            items = items.filter { $0.status != "trashed" }
        }
        var onlyProject: Project?
        if let project = params["project"] {
            guard let text = project as? String, !text.isEmpty else {
                throw Failure(code: "bad_params", message: "project must be a name, a folder path or none.")
            }
            if text == "none" {
                items = items.filter { $0.project == nil }
            } else {
                guard let found = findProject(text) else { throw Failure(code: "not_found", message: "No project \(text).") }
                onlyProject = found
                items = items.filter { item in item.project.map { Router.samePath($0, found.path) } ?? false }
            }
        }
        if let hours = params["maxAgeHours"] {
            guard let number = hours as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue > 0, number.doubleValue.isFinite else {
                throw Failure(code: "bad_params", message: "maxAgeHours must be a number above 0.")
            }
            let oldest = Date().addingTimeInterval(-number.doubleValue * 3600)
            items = items.filter { item in item.at.map { $0 >= oldest } ?? false }
        }
        guard let groupBy = params["groupBy"] else { return ["items": items.map(Self.dictionary)] }
        guard let by = groupBy as? String, by == "project" else {
            throw Failure(code: "bad_params", message: "groupBy can only be project.")
        }
        return ["groups": groups(of: items)]
    }

    private func groups(of items: [Item]) -> [[String: Any]] {
        var buckets: [(project: Project?, items: [Item])] = orderedProjects().projects.map { ($0, []) }
        var noProject: [Item] = []
        for item in items {
            guard let path = item.project else { noProject.append(item); continue }
            if let index = buckets.firstIndex(where: { $0.project.map { Router.samePath($0.path, path) } ?? false }) {
                buckets[index].items.append(item)
            } else {
                buckets.append((Project(name: URL(fileURLWithPath: path).lastPathComponent, path: path), [item]))
            }
        }
        buckets.append((nil, noProject))
        var result: [[String: Any]] = []
        for bucket in buckets where !bucket.items.isEmpty {
            let project: Any = bucket.project.map { ["name": $0.name, "path": $0.path] as [String: Any] } ?? NSNull()
            result.append(["project": project, "items": Self.newestFirst(bucket.items).map(Self.dictionary)])
        }
        return result
    }

    /// Newest first by the item's date; items with no date go last; equal dates keep their order.
    private static func newestFirst(_ items: [Item]) -> [Item] {
        items.enumerated().sorted { first, second in
            switch (first.element.at, second.element.at) {
            case let (one?, two?): return one != two ? one > two : first.offset < second.offset
            case (nil, nil): return first.offset < second.offset
            case (_?, nil): return true
            case (nil, _?): return false
            }
        }.map(\.element)
    }

    /// The known projects in picker order: the live ones first (order of first appearance of each live folder), then the
    /// others by name ignoring case. `liveCount` is how many come first; `agents` has the agent names of each live one.
    private func orderedProjects() -> (projects: [Project], liveCount: Int, agents: [[String]]) {
        let live = loadLive()
        var all: [Project] = []
        for project in Projects.known(file: loadProjects(), live: live) where !all.contains(where: { Router.samePath($0.path, project.path) }) {
            all.append(project)
        }
        var liveOnes: [Project] = []
        var agents: [[String]] = []
        for session in live {
            guard let project = all.first(where: { Router.samePath($0.path, session.cwd) }) else { continue }
            if let index = liveOnes.firstIndex(where: { Router.samePath($0.path, project.path) }) {
                if !agents[index].contains(session.agent) { agents[index].append(session.agent) }
            } else {
                liveOnes.append(project)
                agents.append([session.agent])
            }
        }
        let others = all.enumerated()
            .filter { entry in !liveOnes.contains { Router.samePath($0.path, entry.element.path) } }
            .sorted { first, second in
                let order = first.element.name.caseInsensitiveCompare(second.element.name)
                return order != .orderedSame ? order == .orderedAscending : first.offset < second.offset
            }
            .map(\.element)
        return (liveOnes + others, liveOnes.count, agents)
    }

    private func projectsList(_ params: [String: Any]) throws -> Any {
        let order = orderedProjects()
        let items = loadItems()
        var entries: [[String: Any]] = []
        for (index, project) in order.projects.enumerated() {
            let isLive = index < order.liveCount
            let own = items.filter { item in item.project.map { Router.samePath($0, project.path) } ?? false }
            var entry: [String: Any] = [
                "name": project.name, "path": project.path, "aliases": project.aliases,
                "live": isLive,
                "agents": isLive ? order.agents[index] : [String](),
                "open": own.filter { $0.status == "open" }.count,
                "inProgress": own.filter { $0.status == "in_progress" }.count,
            ]
            if isLive, index < 9 { entry["key"] = index + 1 }
            entries.append(entry)
        }
        return ["projects": entries]
    }

    private func itemsGet(_ params: [String: Any]) throws -> Any {
        guard let id = params["id"] as? String, !id.isEmpty else { throw Failure(code: "bad_params", message: "id is needed.") }
        guard let item = loadItems().first(where: { $0.id == id }) else { throw Failure(code: "not_found", message: "No item \(id).") }
        return ["item": Self.dictionary(item)]
    }

    private func itemsReroute(_ params: [String: Any]) throws -> Any {
        guard let id = params["id"] as? String, !id.isEmpty else { throw Failure(code: "bad_params", message: "id is needed.") }
        guard let name = params["project"] as? String, !name.isEmpty else { throw Failure(code: "bad_params", message: "project is needed.") }
        guard let project = findProject(name) else { throw Failure(code: "not_found", message: "No project \(name).") }
        switch reroute(id, project) {
        case .moved: return ["moved": true]
        case .missing: throw Failure(code: "not_found", message: "No item \(id).")
        case .done: throw Failure(code: "refused", message: "A done item cannot be moved.")
        case .saveFailed: throw Failure(code: "not_available", message: "Could not save the move.")
        }
    }

    private func itemsChangeStatus(_ params: [String: Any], status: String, key: String) throws -> Any {
        guard let id = params["id"] as? String, !id.isEmpty else { throw Failure(code: "bad_params", message: "id is needed.") }
        var note: String?
        if status == "done", let value = params["note"] {
            guard let text = value as? String else { throw Failure(code: "bad_params", message: "note must be text.") }
            note = text.isEmpty ? nil : text
        }
        switch changeStatus(id, status, note) {
        case .changed: return [key: true]
        case .missing: throw Failure(code: "not_found", message: "No item \(id).")
        case .saveFailed: throw Failure(code: "not_available", message: "Could not save the change.")
        }
    }

    private func itemsUnroute(_ params: [String: Any]) throws -> Any {
        guard let id = params["id"] as? String, !id.isEmpty else { throw Failure(code: "bad_params", message: "id is needed.") }
        switch unroute(id) {
        case .unrouted: return ["unrouted": true]
        case .missing: throw Failure(code: "not_found", message: "No item \(id).")
        case .taken: throw Failure(code: "refused", message: "An agent already took this item, so it cannot be unsent.")
        case .saveFailed: throw Failure(code: "not_available", message: "Could not remove the route.")
        }
    }

    private func windowStartDrag(_ params: [String: Any]) throws -> Any {
        guard let startDrag else { throw Failure(code: "not_available", message: "Dragging the window is not available.") }
        startDrag()
        return ["dragging": true]
    }

    private func clipboardCopy(_ params: [String: Any]) throws -> Any {
        guard let text = params["text"] as? String, !text.isEmpty else { throw Failure(code: "bad_params", message: "text must be a non-empty string.") }
        writeClipboard(text)
        return ["copied": true]
    }

    private func questionsList(_ params: [String: Any]) throws -> Any {
        ["questions": Questions.pending().map(Self.dictionary)]
    }

    private func questionsAnswer(_ params: [String: Any]) throws -> Any {
        guard let id = params["id"] as? String, !id.isEmpty else { throw Failure(code: "bad_params", message: "id is needed.") }
        guard let text = params["text"] as? String, !text.isEmpty else { throw Failure(code: "bad_params", message: "text is needed.") }
        guard Questions.answer(id: id, text: text) else { throw Failure(code: "not_found", message: "No open question \(id).") }
        return ["answered": true]
    }

    private func settingsGet(_ params: [String: Any]) throws -> Any {
        if let key = params["key"] {
            guard let name = key as? String, let kind = Self.kind(of: name) else { throw Failure(code: "refused", message: "That setting cannot be read.") }
            return ["key": name, "value": value(name, kind)]
        }
        var values: [String: Any] = [:]
        for entry in Self.allowedSettings { values[entry.key] = value(entry.key, entry.kind) }
        return ["values": values]
    }

    private func settingsSet(_ params: [String: Any]) throws -> Any {
        guard let name = params["key"] as? String, let kind = Self.kind(of: name) else {
            throw Failure(code: "refused", message: "That setting cannot be changed.")
        }
        switch kind {
        case .flag:
            guard let number = params["value"] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw Failure(code: "bad_params", message: "\(name) is on or off (true or false).")
            }
            defaults.set(number.boolValue, forKey: name)
        case .choice(let allowed, _):
            guard let text = params["value"] as? String, allowed.contains(text) else {
                throw Failure(code: "bad_params", message: "\(name) must be one of the known values.")
            }
            defaults.set(text, forKey: name)
        }
        return ["key": name, "value": value(name, kind)]
    }

    private func statusGet(_ params: [String: Any]) throws -> Any {
        ["status": loadStatus().dictionary]
    }

    private func permissionsAsk(_ params: [String: Any]) throws -> Any {
        guard let which = params["which"] as? String, AppStatus.permissionNames.contains(which) else {
            throw Failure(code: "bad_params", message: "which must be microphone, screenRecording or accessibility.")
        }
        guard let askPermission else { throw Failure(code: "not_available", message: "Asking for a permission is not available yet.") }
        askPermission(which)
        return ["asked": true]
    }

    private static func kind(of key: String) -> SettingKind? {
        allowedSettings.first { $0.key == key }?.kind
    }

    private func value(_ key: String, _ kind: SettingKind) -> Any {
        switch kind {
        case .flag(let defaultValue): return defaults.object(forKey: key) as? Bool ?? defaultValue
        case .choice(_, let defaultValue): return defaults.string(forKey: key) ?? defaultValue
        }
    }

    static func dictionary(_ question: Question) -> [String: Any] {
        ["id": question.id, "project": question.project, "agent": question.agent, "text": question.text,
         "choices": question.choices, "asked": question.asked.timeIntervalSince1970]
    }

    static func dictionary(_ item: Item) -> [String: Any] {
        var out: [String: Any] = [
            "id": item.id, "session": item.session, "n": item.n, "title": item.title, "body": item.body,
            "crops": item.crops.map(\.path), "status": item.status,
        ]
        out["cropURLs"] = item.crops.compactMap { crop -> String? in
            guard let relative = WebImages.relativePath(of: crop, session: item.session, root: Paths.root) else { return nil }
            return WebImages.url(session: item.session, relative: relative)
        }
        let afterFile = Paths.root.appendingPathComponent(item.session).appendingPathComponent("after/01.jpg")
        if !item.session.isEmpty, FileManager.default.fileExists(atPath: afterFile.path) {
            out["afterURL"] = WebImages.url(session: item.session, relative: "after/01.jpg")
        }
        if let at = item.at { out["at"] = ISO8601DateFormatter().string(from: at) }
        if let by = item.by { out["by"] = by }
        if let note = item.note { out["note"] = note }
        if let project = item.project { out["project"] = project }
        if let how = item.routeHow { out["routeHow"] = how }
        if let priority = item.priority { out["priority"] = priority }
        if let commit = item.commit { out["commit"] = commit }
        if let branch = item.branch { out["branch"] = branch }
        if let duplicateOf = item.duplicateOf { out["duplicateOf"] = duplicateOf }
        out["alsoSaid"] = item.alsoSaid
        if !item.said.isEmpty { out["said"] = item.said }
        if let firstElement = item.firstElement { out["firstElement"] = firstElement }
        if item.duration > 0 { out["duration"] = item.duration }
        return out
    }
}
