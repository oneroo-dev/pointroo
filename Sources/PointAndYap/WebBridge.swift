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
///   recording.changed  {phase, pointCount}         phase is "idle", "recording", "processing" or "picking" (the project picker is open)
///   picker.changed     {open, session?}            the project picker opened or closed (session is the recording it asks about)
///   notices.changed    {count}                     the set of notices (unseen agent-done items and pending questions) changed
///   status.changed     {mcpRunning, mcpPort, mcpText, sessions, agents, microphone, screenRecording, accessibility}
///                      the same object status.get returns inside `status`; sent when any part of it changed
///
/// Error codes: bad_request (not valid JSON, or no method), unknown_method, bad_params, not_found, not_available, refused,
/// busy (a recording call that does not fit the phase now).
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
///                   result {projects: [{name, path, aliases: [string], live: bool, agents: [string], key?: 1...9, open, inProgress, lastUsed?}]}
///                   live projects come first (in picker order), then the others, newest lastUsed first, then by name ignoring case.
///                   `key` is the picker's number key, given to the first nine live projects only. `open` and `inProgress` count the
///                   items routed to that folder. `lastUsed` is the ISO date of the newest item routed there (its `at`, else the time
///                   of its recording); left out when there is none.
///   items.get       params {id: string}
///                   result {item: Item}   error not_found when there is no such item
///   items.search    params {text: string 1...200 characters, status?: "open" | "in_progress" | "done" | "trashed" | "any", limit?: whole number 1...100, default 30}
///                   status    no status = every item except the trashed ones; "any" = every item, trashed too
///                   matching  case and accents ignored; every word of text must be found in the item's title, body, said, alsoSaid, note,
///                   project name or firstElement. Title hits come first, then said/body, then the rest; inside a rank the newest comes first.
///                   result {items: [Item + match: {field, snippet}]}   field is the best field with a hit; snippet is up to 80
///                   characters around the first hit, on one line
///                   error bad_params (text empty or longer than 200, status not allowed, limit not a whole number 1...100)
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
///   server.useAnotherPort no params   moves the agents server to the next free port, then the agent install follows it
///                   result {asked: true}   error not_available when the app gave no way to do it
///   app.checkUpdates no params   asks the updater to look for a new version
///                   result {asked: true}   error not_available when the app gave no way to do it
///   done.recent     params {limit?: whole number 1...50, default 10}
///                   result {items: [Item + doneAt]}   items with status done, newest done first (doneAt is the ISO date it was marked done,
///                   the same value as the item's `at`; an item with no date goes last and has no doneAt). Each Item has project, note,
///                   by, crops and cropURLs (the before pictures) and afterURL (the after picture of the done banner, when it exists).
///                   error bad_params when limit is not a whole number from 1 to 50
///   notices.list    params {limit?: whole number 1...50, default 20}
///                   result {notices: [Notice]}   newest first: done items an agent finished that the user has not seen (never by "you" or
///                   "user"), mixed with the pending questions. Done: {kind: "done", id (the item id), agent, project?, projectName?, note?,
///                   cropURL? (first crop), afterURL?, at?}. Question: the Question keys plus kind: "question".
///                   error bad_params when limit is not a whole number from 1 to 50
///   notices.seen    params {ids: [string]}   marks done items as seen (the newest 500 are kept). Ids that are not done items are ignored;
///                   questions leave the list when answered or snoozed.
///                   result {seen: number of ids that were done items}   error bad_params (ids is not a list of text), not_available (could not save)
///   session.get     params {session: string}   the id of a recording (an item's `session`)
///                   result {session, started: ISO date, duration: seconds, said: [{text, start, end}] (every spoken word, seconds from the start),
///                   points: [{at: seconds from the start, x, y, app?, window?, url?, element?}] (element is a short text like AXButton "Save"),
///                   frames: [pointroo-image:// address] (the full screenshots that exist), items: [item id]}
///                   error bad_params when session is missing, empty, or has a "/" or ".." in it, not_found when there is no such recording
///   questions.list  no params
///                   result {questions: [Question]}   unanswered questions from agents, oldest first; snoozed ones are left out until their time
///   questions.answer params {id: string, text: string}
///                   result {answered: true}   error not_found when the question is unknown or already answered, bad_params when id or text is missing
///   questions.later params {id: string, minutes?: whole number 1...1440, default 30}   snoozes the question: questions.list leaves it out
///                   until that many minutes from now, then it comes back (and questions.changed is sent both times)
///                   result {snoozed: true, until: seconds since 1970}
///                   error not_found when the question is unknown or already answered, bad_params when id is missing or minutes is out of range
///   recording.start params {followUp?: item id}   the same as double Control while idle (AppState.start). With followUp, the
///                   item must be done and routed to a project, and the recording is routed there as its follow-up (the request is kept
///                   in follow-next.json, used once, and ignored when older than 10 minutes)
///                   result {started: true, followUp?: item id}   error busy (recording, or the last one is processing; checked first),
///                   bad_params (followUp is not a done item that went to a project), not_available
///   recording.stop  no params   result {stopped: true}   error busy (not recording), not_available
///   recording.cancel no params  stops and keeps nothing; result {cancelled: true}   error busy (not recording), not_available
///                   (start can still fail inside the app, for example when a permission is missing; the page sees that in recording.get)
///   recording.get   no params
///                   result {phase: "idle" | "recording" | "processing" | "picking", startedAt?: ISO date (only while recording),
///                   points: number, words?: [string] (the last few spoken words, when the app has them)}   error not_available
///   picker.get      no params
///                   result {open: false} or {open: true, session?: string, choices: [{name, path, key, suggested}] (in number-key order,
///                   key is 1...9, suggested is true for the folder the router guessed), countdown?: whole seconds before it skips by itself}
///   picker.pick     params {path: string}   answers the open picker like a click on that project; the recording is sent there and the router learns it
///                   result {picked: true}   error bad_params (no path, or not one of the choices), not_found (no picker open, or it was answered already), not_available
///   picker.skip     no params   answers the open picker like Esc: the recording stays in the queue
///                   result {skipped: true}   error not_found (no picker open, or it was answered already), not_available
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
///        suggested?, suggestedName?, priority?, commit?, branch?, duplicateOf?, said?, firstElement?, duration?}
///   suggested     the folder the router guesses for a recording it did not send (only while the item has no project)
///   suggestedName that project's name
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
/// Settings keys: sounds, doubleControl, escCancels, redactSecrets, connectAgents, showNoSpeech, holdToTalk, listenAfterDone, kitWindow, autoSendSingle (all bool; autoSendSingle is on when never set);
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
        ("autoSendSingle", .flag(defaultValue: true)),
        ("locale", .choice(allowed: Prefs.languages.map(\.id), defaultValue: "")),
    ]

    /// The whitelist. A method that is not here is an error.
    static let methods: [String: Handler] = [
        "items.list": { bridge, params in try bridge.itemsList(params) },
        "projects.list": { bridge, params in try bridge.projectsList(params) },
        "items.get": { bridge, params in try bridge.itemsGet(params) },
        "items.search": { bridge, params in try bridge.itemsSearch(params) },
        "items.reroute": { bridge, params in try bridge.itemsReroute(params) },
        "items.done": { bridge, params in try bridge.itemsChangeStatus(params, status: "done", key: "done") },
        "items.reopen": { bridge, params in try bridge.itemsChangeStatus(params, status: "open", key: "reopened") },
        "items.trash": { bridge, params in try bridge.itemsChangeStatus(params, status: "trashed", key: "trashed") },
        "items.unroute": { bridge, params in try bridge.itemsUnroute(params) },
        "clipboard.copy": { bridge, params in try bridge.clipboardCopy(params) },
        "window.startDrag": { bridge, params in try bridge.windowStartDrag(params) },
        "questions.list": { bridge, params in try bridge.questionsList(params) },
        "questions.answer": { bridge, params in try bridge.questionsAnswer(params) },
        "questions.later": { bridge, params in try bridge.questionsLater(params) },
        "done.recent": { bridge, params in try bridge.doneRecent(params) },
        "notices.list": { bridge, params in try bridge.noticesList(params) },
        "notices.seen": { bridge, params in try bridge.noticesSeen(params) },
        "session.get": { bridge, params in try bridge.sessionGet(params) },
        "recording.start": { bridge, params in try bridge.recordingControl(.start, params: params) },
        "recording.stop": { bridge, params in try bridge.recordingControl(.stop, params: params) },
        "recording.cancel": { bridge, params in try bridge.recordingControl(.cancel, params: params) },
        "recording.get": { bridge, params in try bridge.recordingGet(params) },
        "picker.get": { bridge, params in try bridge.pickerGet(params) },
        "picker.pick": { bridge, params in try bridge.pickerPick(params) },
        "picker.skip": { bridge, params in try bridge.pickerSkip(params) },
        "settings.get": { bridge, params in try bridge.settingsGet(params) },
        "settings.set": { bridge, params in try bridge.settingsSet(params) },
        "status.get": { bridge, params in try bridge.statusGet(params) },
        "permissions.ask": { bridge, params in try bridge.permissionsAsk(params) },
        "server.useAnotherPort": { bridge, params in try bridge.serverUseAnotherPort(params) },
        "app.checkUpdates": { bridge, params in try bridge.appCheckUpdates(params) },
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
    private let controlRecording: ((RecordingAction) -> Void)?
    private let loadRecording: (() -> RecordingSnapshot)?
    private let loadPicker: (() -> PickerSnapshot?)?
    private let answerPicker: ((String?) -> Bool)?
    private let useAnotherPort: (() -> Void)?
    private let checkUpdates: (() -> Void)?
    private let now: () -> Date
    private let loadQuestions: (Date) -> [Question]
    private let noticeStore: NoticeStore
    private let followUpStore: FollowUpStore

    /// What recording.start, recording.stop and recording.cancel ask the app to do.
    enum RecordingAction {
        case start
        case stop
        case cancel
    }

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
    /// `controlRecording` runs the start, stop or cancel (AppState.start, stop, cancel); `loadRecording` gives the recording snapshot
    /// (the same one recording.changed uses); both nil means recording.* answers not_available (recording.get needs `loadRecording`).
    /// `loadPicker` gives the open project picker or nil; `answerPicker` answers it with a folder path (nil = skip) the way a click or
    /// Esc does, and returns false when no picker was open any more. Either one nil means picker.* answers not_available.
    /// `useAnotherPort` serves server.useAnotherPort and `checkUpdates` serves app.checkUpdates; when one is nil, its method answers not_available.
    /// `now` is the clock for the question snooze (tests set it).
    /// `loadQuestions` (given `now`) gives the pending questions for notices.list; `noticeStore` is where notices.seen keeps the seen ids.
    /// `followUpStore` is where recording.start keeps a follow-up request (recording.cancel removes it).
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
         startDrag: (() -> Void)? = nil,
         controlRecording: ((RecordingAction) -> Void)? = nil,
         loadRecording: (() -> RecordingSnapshot)? = nil,
         loadPicker: (() -> PickerSnapshot?)? = nil,
         answerPicker: ((String?) -> Bool)? = nil,
         useAnotherPort: (() -> Void)? = nil,
         checkUpdates: (() -> Void)? = nil,
         now: @escaping () -> Date = { Date() },
         loadQuestions: @escaping (Date) -> [Question] = { Questions.pending(now: $0) },
         noticeStore: NoticeStore = NoticeStore(),
         followUpStore: FollowUpStore = FollowUpStore()) {
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
        self.controlRecording = controlRecording
        self.loadRecording = loadRecording
        self.loadPicker = loadPicker
        self.answerPicker = answerPicker
        self.useAnotherPort = useAnotherPort
        self.checkUpdates = checkUpdates
        self.now = now
        self.loadQuestions = loadQuestions
        self.noticeStore = noticeStore
        self.followUpStore = followUpStore
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
        if let project = params["project"] {
            guard let text = project as? String, !text.isEmpty else {
                throw Failure(code: "bad_params", message: "project must be a name, a folder path or none.")
            }
            if text == "none" {
                items = items.filter { $0.project == nil }
            } else {
                guard let found = findProject(text) else { throw Failure(code: "not_found", message: "No project \(text).") }
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
        let items = loadItems()
        let others = all.enumerated()
            .filter { entry in !liveOnes.contains { Router.samePath($0.path, entry.element.path) } }
            .map { entry in (offset: entry.offset, project: entry.element, used: Self.lastUsed(of: entry.element.path, in: items)) }
            .sorted { first, second in
                if first.used != second.used {
                    switch (first.used, second.used) {
                    case let (one?, two?): return one > two
                    case (_?, nil): return true
                    default: return false
                    }
                }
                let order = first.project.name.caseInsensitiveCompare(second.project.name)
                return order != .orderedSame ? order == .orderedAscending : first.offset < second.offset
            }
            .map(\.project)
        return (liveOnes + others, liveOnes.count, agents)
    }

    /// The newest time among the items routed to this folder: the item's date, else the time its recording started.
    static func lastUsed(of path: String, in items: [Item]) -> Date? {
        items.filter { item in item.project.map { Router.samePath($0, path) } ?? false }
            .compactMap { $0.at ?? Items.recordedAt($0.session) }
            .max()
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
            if let used = Self.lastUsed(of: project.path, in: items) { entry["lastUsed"] = ISO8601DateFormatter().string(from: used) }
            entries.append(entry)
        }
        return ["projects": entries]
    }

    private func itemsGet(_ params: [String: Any]) throws -> Any {
        guard let id = params["id"] as? String, !id.isEmpty else { throw Failure(code: "bad_params", message: "id is needed.") }
        guard let item = loadItems().first(where: { $0.id == id }) else { throw Failure(code: "not_found", message: "No item \(id).") }
        return ["item": Self.dictionary(item)]
    }

    private func itemsSearch(_ params: [String: Any]) throws -> Any {
        guard let text = params["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= 200 else {
            throw Failure(code: "bad_params", message: "text must be 1 to 200 characters.")
        }
        var items = loadItems()
        if let status = params["status"] {
            guard let wanted = status as? String, ["open", "in_progress", "done", "trashed", "any"].contains(wanted) else {
                throw Failure(code: "bad_params", message: "status must be open, in_progress, done, trashed or any.")
            }
            if wanted != "any" { items = items.filter { $0.status == wanted } }
        } else {
            items = items.filter { $0.status != "trashed" }
        }
        let limit = try Self.wholeNumber(params["limit"], named: "limit", range: 1...100, defaultValue: 30)
        let found = ItemSearch.matches(items, text: text).prefix(limit)
        return ["items": found.map { match -> [String: Any] in
            var entry = Self.dictionary(match.item)
            entry["match"] = ["field": match.field, "snippet": match.snippet]
            return entry
        }]
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

    private func serverUseAnotherPort(_ params: [String: Any]) throws -> Any {
        guard let useAnotherPort else { throw Failure(code: "not_available", message: "Using another port is not available.") }
        useAnotherPort()
        return ["asked": true]
    }

    private func appCheckUpdates(_ params: [String: Any]) throws -> Any {
        guard let checkUpdates else { throw Failure(code: "not_available", message: "Checking for updates is not available.") }
        checkUpdates()
        return ["asked": true]
    }

    private func recordingControl(_ action: RecordingAction, params: [String: Any] = [:]) throws -> Any {
        guard let controlRecording, let loadRecording else {
            throw Failure(code: "not_available", message: "Recording is not available.")
        }
        let phase = loadRecording().phase
        switch action {
        case .start:
            if phase == "recording" { throw Failure(code: "busy", message: "Already recording.") }
            if phase == "processing" { throw Failure(code: "busy", message: "The last recording is still being processed.") }
            var followUpId: String?
            var request: FollowUpRequest?
            if let value = params["followUp"], !(value is NSNull) {
                let badFollowUp = Failure(code: "bad_params", message: "followUp must be a done item that went to a project.")
                guard let id = value as? String, !id.isEmpty,
                      let item = loadItems().first(where: { $0.id == id }),
                      item.status == "done", let path = item.project, !path.isEmpty else { throw badFollowUp }
                followUpId = id
                request = FollowUpRequest(id: id, path: path, at: now())
            }
            if let request {
                guard followUpStore.save(request) else { throw Failure(code: "not_available", message: "Could not save the follow-up request.") }
            }
            controlRecording(.start)
            if let followUpId { return ["started": true, "followUp": followUpId] }
            return ["started": true]
        case .stop:
            guard phase == "recording" else { throw Failure(code: "busy", message: "Not recording.") }
            controlRecording(.stop)
            return ["stopped": true]
        case .cancel:
            guard phase == "recording" else { throw Failure(code: "busy", message: "Not recording.") }
            followUpStore.remove()
            controlRecording(.cancel)
            return ["cancelled": true]
        }
    }

    private func recordingGet(_ params: [String: Any]) throws -> Any {
        guard let loadRecording else { throw Failure(code: "not_available", message: "Recording is not available.") }
        let snapshot = loadRecording()
        var out: [String: Any] = ["phase": snapshot.phase, "points": snapshot.points]
        if let startedAt = snapshot.startedAt { out["startedAt"] = ISO8601DateFormatter().string(from: startedAt) }
        if !snapshot.words.isEmpty { out["words"] = snapshot.words }
        return out
    }

    private func pickerGet(_ params: [String: Any]) throws -> Any {
        guard let loadPicker else { throw Failure(code: "not_available", message: "The project picker is not available.") }
        guard let snapshot = loadPicker() else { return ["open": false] }
        var out: [String: Any] = [
            "open": true,
            "choices": snapshot.choices.map { choice -> [String: Any] in
                ["name": choice.name, "path": choice.path, "key": choice.key, "suggested": choice.suggested]
            },
        ]
        if let session = snapshot.session { out["session"] = session }
        if let countdown = snapshot.countdown { out["countdown"] = countdown }
        return out
    }

    private func pickerPick(_ params: [String: Any]) throws -> Any {
        guard let path = params["path"] as? String, !path.isEmpty else { throw Failure(code: "bad_params", message: "path is needed.") }
        guard let loadPicker, let answerPicker else { throw Failure(code: "not_available", message: "The project picker is not available.") }
        guard let snapshot = loadPicker() else { throw Failure(code: "not_found", message: "No project picker is open.") }
        guard let choice = snapshot.choices.first(where: { Router.samePath($0.path, path) }) else {
            throw Failure(code: "bad_params", message: "That folder is not one of the choices.")
        }
        guard answerPicker(choice.path) else { throw Failure(code: "not_found", message: "No project picker is open.") }
        return ["picked": true]
    }

    private func pickerSkip(_ params: [String: Any]) throws -> Any {
        guard let loadPicker, let answerPicker else { throw Failure(code: "not_available", message: "The project picker is not available.") }
        guard loadPicker() != nil, answerPicker(nil) else { throw Failure(code: "not_found", message: "No project picker is open.") }
        return ["skipped": true]
    }

    private func clipboardCopy(_ params: [String: Any]) throws -> Any {
        guard let text = params["text"] as? String, !text.isEmpty else { throw Failure(code: "bad_params", message: "text must be a non-empty string.") }
        writeClipboard(text)
        return ["copied": true]
    }

    private func questionsList(_ params: [String: Any]) throws -> Any {
        ["questions": Questions.pending(now: now()).map(Self.dictionary)]
    }

    private func questionsLater(_ params: [String: Any]) throws -> Any {
        guard let id = params["id"] as? String, !id.isEmpty else { throw Failure(code: "bad_params", message: "id is needed.") }
        let minutes = try Self.wholeNumber(params["minutes"], named: "minutes", range: 1...1440, defaultValue: 30)
        let start = now()
        guard Questions.snooze(id: id, minutes: minutes, now: start) else { throw Failure(code: "not_found", message: "No open question \(id).") }
        return ["snoozed": true, "until": start.addingTimeInterval(TimeInterval(minutes) * 60).timeIntervalSince1970]
    }

    /// A whole number inside `range` from the page, or `defaultValue` when the page left it out.
    private static func wholeNumber(_ value: Any?, named name: String, range: ClosedRange<Int>, defaultValue: Int) throws -> Int {
        guard let value else { return defaultValue }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue == number.doubleValue.rounded(), range.contains(number.intValue) else {
            throw Failure(code: "bad_params", message: "\(name) must be a whole number from \(range.lowerBound) to \(range.upperBound).")
        }
        return number.intValue
    }

    private func doneRecent(_ params: [String: Any]) throws -> Any {
        let limit = try Self.wholeNumber(params["limit"], named: "limit", range: 1...50, defaultValue: 10)
        let done = loadItems().filter { $0.status == "done" }
        let newest = Self.newestFirst(done).prefix(limit)
        let items = newest.map { item -> [String: Any] in
            var entry = Self.dictionary(item)
            if let at = item.at { entry["doneAt"] = ISO8601DateFormatter().string(from: at) }
            return entry
        }
        return ["items": items]
    }

    private func noticesList(_ params: [String: Any]) throws -> Any {
        let limit = try Self.wholeNumber(params["limit"], named: "limit", range: 1...50, defaultValue: 20)
        let seen = Set(noticeStore.seenIds())
        var entries: [(date: Date, entry: [String: Any])] = []
        for item in loadItems() where Notices.isUnseenDone(item, seen: seen) {
            entries.append((item.at ?? .distantPast, Self.doneNotice(item)))
        }
        for question in loadQuestions(now()) {
            entries.append((question.asked, Self.questionNotice(question)))
        }
        let newest = entries.enumerated().sorted { first, second in
            first.element.date != second.element.date ? first.element.date > second.element.date : first.offset < second.offset
        }.prefix(limit)
        return ["notices": newest.map { $0.element.entry }]
    }

    private func noticesSeen(_ params: [String: Any]) throws -> Any {
        guard let list = params["ids"] as? [Any] else { throw Failure(code: "bad_params", message: "ids must be a list of item ids.") }
        var ids: [String] = []
        for value in list {
            guard let id = value as? String else { throw Failure(code: "bad_params", message: "ids must be a list of item ids.") }
            ids.append(id)
        }
        let done = Set(loadItems().filter { $0.status == "done" }.map(\.id))
        let known = ids.filter { done.contains($0) }
        guard noticeStore.markSeen(known) else { throw Failure(code: "not_available", message: "Could not save the seen notices.") }
        return ["seen": known.count]
    }

    private static func doneNotice(_ item: Item) -> [String: Any] {
        let base = dictionary(item)
        var out: [String: Any] = ["kind": "done", "id": item.id, "agent": item.by ?? ""]
        if let project = item.project {
            out["project"] = project
            out["projectName"] = Projects.name(for: project)
        }
        if let note = item.note { out["note"] = note }
        if let cropURL = (base["cropURLs"] as? [String])?.first { out["cropURL"] = cropURL }
        if let afterURL = base["afterURL"] { out["afterURL"] = afterURL }
        if let at = base["at"] { out["at"] = at }
        return out
    }

    private static func questionNotice(_ question: Question) -> [String: Any] {
        var out = dictionary(question)
        out["kind"] = "question"
        return out
    }

    private func sessionGet(_ params: [String: Any]) throws -> Any {
        guard let id = params["session"] as? String, !id.isEmpty, !id.contains("/"), !id.contains("..") else {
            throw Failure(code: "bad_params", message: "session must be a recording id, with no / or ..")
        }
        guard let folder = MCPServer.dir(id),
              let data = try? Data(contentsOf: folder.appendingPathComponent("events.json")),
              let events = try? JSONDecoder.iso.decode(SessionEvents.self, from: data) else {
            throw Failure(code: "not_found", message: "No recording \(id).")
        }
        let words = (try? Data(contentsOf: folder.appendingPathComponent("transcript.json")))
            .flatMap { try? JSONDecoder().decode([Word].self, from: $0) } ?? []
        let points = events.points.map { point -> [String: Any] in
            var entry: [String: Any] = ["at": point.t, "x": point.at.x, "y": point.at.y]
            if let app = point.app { entry["app"] = app }
            if let window = point.window { entry["window"] = window }
            if let url = point.url { entry["url"] = url }
            if point.element != nil { entry["element"] = Builder.describe(point) }
            return entry
        }
        let frames = events.frames
            .filter { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.file).path) }
            .map { WebImages.url(session: id, relative: $0.file) }
        let itemIds = Items.items(in: folder, state: Items.readState(folder)).items.map(\.id)
        return [
            "session": id,
            "started": ISO8601DateFormatter().string(from: events.started),
            "duration": events.duration,
            "said": words.map { ["text": $0.text, "start": $0.start, "end": $0.end] as [String: Any] },
            "points": points,
            "frames": frames,
            "items": itemIds,
        ] as [String: Any]
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
        if let suggested = item.suggested {
            out["suggested"] = suggested
            out["suggestedName"] = Projects.name(for: suggested)
        }
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
