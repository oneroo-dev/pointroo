import AppKit
import AVFoundation
import SwiftUI

struct SessionRow: Identifiable, Equatable {
    var id: String { dir.path }
    var dir: URL
    var date: Date
    var duration: Int
    var points: Int
    var title: String
    var status = ""     // open, in_progress, done; empty when nothing was said
    var by: String?
    var note: String?
    var noSpeech = false
}

@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable { case idle, recording(Date), processing }

    @Published var phase: Phase = .idle
    @Published var sessions: [SessionRow] = []
    @Published var toast: String?
    @Published var mic = false
    @Published var screen = false
    @Published var ax = false
    @Published var showSettings = false
    /// The how-it-works card: until Got it once, and whenever How it works is pressed.
    @Published var showWelcome = !UserDefaults.standard.bool(forKey: "welcomeSeen")

    func dismissWelcome() {
        UserDefaults.standard.set(true, forKey: "welcomeSeen")
        showWelcome = false
    }
    /// A new version downloaded and ready to install (Updater).
    @Published var updateReady: String?
    /// The points added so far in the recording that is running (0 when idle); the pill shows it.
    @Published var pointCount = 0
    /// The item the main window should show (set by a pointroo://item/<id> link or by the list).
    @Published var selectedItem: String?
    /// The next recording is a practice one (the "Try it" card): it is done by "you" at once.
    @Published var practiceNext = false
    /// The coding agents found on this Mac, while the first-run question is open.
    @Published var askAgents: [String] = []

    private var recorder: Recorder?
    var onRecordingChanged: ((Bool) -> Void)?
    /// The pill's frame in global top-left points: clicks there are not points.
    var ownUI: (() -> CGRect?)?

    var allowed: Bool { mic && screen && ax }
    func refreshAccess() {
        mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        screen = CGPreflightScreenCaptureAccess()
        ax = AXProbe.trusted
    }

    func askMic() { Task { _ = await AudioRecorder.askForAccess(); refreshAccess() } }
    func askScreen() {
        Relaunch.armForGrant()
        if !CGRequestScreenCaptureAccess() { openSettings("Privacy_ScreenCapture") }
        refreshAccess()
    }
    func askAX() { Relaunch.armForGrant(); AXProbe.askForTrust(); openSettings("Privacy_Accessibility") }

    private func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }

    func start(listening: Bool = false) {
        guard phase == .idle else { return }
        // A recording the user starts themself ends any listen window.
        if !listening { listenWindow.userTookOver(); stopListenTimer() }
        let r = Recorder()
        r.ignore = { [weak self] in self?.ownUI?() }
        r.onPointCount = { [weak self] count in self?.pointCount = count }
        r.onLevel = { [weak self] level in self?.listenLevel(level) }
        pointCount = 0
        do { try r.start() } catch {
            if listening {
                listenWindow.userTookOver()
                stopListenTimer()
            } else {
                say("Couldn't start: \(error.localizedDescription)")
            }
            return
        }
        recorder = r
        phase = .recording(Date())
        if !listening { Sounds.play("start") }
        onRecordingChanged?(true)
    }

    /// Esc while recording: stop and keep nothing.
    func cancel() { cancel(silently: false) }

    /// Stops and keeps nothing. Silently means no sound and no toast: used when a listen window heard nothing.
    func cancel(silently: Bool) {
        guard case .recording = phase, let r = recorder else { return }
        // Esc during a listen window is silent too, and closes the window.
        let wasListening = listenWindow.isListening
        _ = listenWindow.escape()
        stopListenTimer()
        recorder = nil
        r.cancel()
        pointCount = 0
        phase = .idle
        onRecordingChanged?(false)
        if Prefs.sounds, !silently, !wasListening { NSSound(named: "Pop")?.play() }
        loadSessions()
    }

    /// The user pressed and held Control while a listen window was recording: the window steps aside and the
    /// recording goes on as a normal hold. True when there was a window to take over.
    func takeOverListening() -> Bool {
        guard listenWindow.isListening, case .recording = phase else { return false }
        listenWindow.userTookOver()
        stopListenTimer()
        return true
    }

    /// Double Control: start when idle, stop while recording.
    func toggle() {
        switch phase {
        case .idle: if allowed { start() } else { NSSound(named: "Basso")?.play() }
        case .recording: stop()
        case .processing: break
        }
    }

    func stop() {
        guard case .recording = phase, let r = recorder else { return }
        listenWindow.userTookOver()
        stopListenTimer()
        recorder = nil
        phase = .processing
        pointCount = 0
        onRecordingChanged?(false)
        let practice = practiceNext
        practiceNext = false
        FloatingWatcher.openReadWindow()
        Task {
            let dir = await r.stop()
            FloatingWatcher.openReadWindow()
            if practice { Practice.mark(dir) }
            loadSessions()
            // The short pointer goes on the clipboard as soon as the timeline exists; the MCP and the folder fill in after.
            _ = await Process.run(dir: dir, onTimeline: {
                self.copyPointer(dir)
                Sounds.play("done")
                if let route = Router.readRoute(dir) { self.say("Sent to \(route.project)") }
                else { self.say("Copied. Paste it into your agent") }
            })
            phase = .idle
            loadSessions()
            await pickProject(dir)
        }
    }

    private var listenWindow = ListenWindow()
    private var listenTimer: Timer?
    private let listenClock = ProcessInfo.processInfo.systemUptime

    /// Seconds on a steady clock, for the listen window.
    private var listenNow: TimeInterval { ProcessInfo.processInfo.systemUptime - listenClock }

    /// Call once at launch: a done banner on screen may open the listen window.
    func wireListenWindow() {
        DoneBanner.shared.onShown = { [weak self] in self?.listenBannerShown() }
    }

    private func listenBannerShown() {
        // Read the mic state now, before Pointroo opens the microphone itself.
        let on = Prefs.listenAfterDone
        let conditions = ListenWindow.Conditions(settingOn: on, phaseIdle: phase == .idle && allowed,
                                                 micBusyElsewhere: on ? ListenSystem.micBusyElsewhere() : false,
                                                 idleSeconds: on ? ListenSystem.idleSeconds() : 0,
                                                 screenLocked: on ? ListenSystem.screenLocked() : false)
        perform(listenWindow.bannerShown(at: listenNow, conditions: conditions))
    }

    private func listenLevel(_ level: Float) {
        listenWindow.level(level, at: listenNow)
    }

    private func listenTick() {
        perform(listenWindow.tick(at: listenNow))
    }

    private func perform(_ actions: [ListenAction]) {
        for action in actions {
            switch action {
            case .start:
                start(listening: true)
                if listenWindow.isListening { startListenTimer() }
            case .cancelSilently: cancel(silently: true)
            case .stop: stop()
            }
        }
        if !listenWindow.isListening { stopListenTimer() }
    }

    private func startListenTimer() {
        listenTimer?.invalidate()
        listenTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.listenTick() }
        }
    }

    private func stopListenTimer() {
        listenTimer?.invalidate()
        listenTimer = nil
    }

    /// No rule routed the recording and several agent sessions are running: ask which project it is for, and learn the answer.
    private func pickProject(_ dir: URL) async {
        guard Router.readRoute(dir) == nil, !Items.items(in: dir, state: nil).items.isEmpty else { return }
        let live = Projects.liveProjects()
        guard live.count >= 2 else { return }
        let suggested = Items.items(in: dir, state: nil).items.first?.suggested
        guard let project = await ProjectPicker.ask(live, session: dir.lastPathComponent, suggested: suggested) else {
            say("Not sent - kept in the queue")
            return
        }
        Router.writeRoute(RouteInfo(project: project.name, path: project.path, how: "picked"), to: dir)
        Projects.learn(from: dir, project: project)
        say("Sent to \(project.name)")
        loadSessions()
    }

    /// Two lines an agent can act on: what is new, and how to get it.
    static func pointer(_ dir: URL) -> String {
        let open = Items.all().filter { $0.status == "open" }.count
        let title = Items.items(in: dir, state: nil).items.first?.title ?? "a recording"
        return "New in Pointroo: \"\(title)…\"\(open > 1 ? " (\(open) recordings to fix)" : "")\n"
            + "Fix them all: the pointroo MCP get_open_items, then mark_done each when it is fixed. "
            + "Without the MCP: \(QueueCLI.binary) --items, and --done <id> --note \"what changed\"."
    }

    private func copyPointer(_ dir: URL) { copy(Self.pointer(dir)) }

    func copy(_ row: SessionRow) {
        copyPointer(row.dir)
        say("Copied")
    }

    /// The user marks a recording done themself, or opens it again.
    func toggleDone(_ row: SessionRow) {
        let ids = Items.items(in: row.dir, state: Items.readState(row.dir)).items.map(\.id)
        guard !ids.isEmpty else { return }
        _ = Items.set(ids, status: row.status == "done" ? "open" : "done", agent: "you", note: nil)
        loadSessions()
        say(row.status == "done" ? "Open again" : "Marked done")
    }

    /// The first-run answer: Connect registers the MCP and skill now and on later launches; Skip touches nothing.
    func answerAgents(_ yes: Bool) {
        UserDefaults.standard.set(yes, forKey: "connectAgents")
        UserDefaults.standard.set(true, forKey: "agentsAsked")
        askAgents = []
        if yes {
            DispatchQueue.global(qos: .userInitiated).async { AgentInstall.run() }
            say("Connected")
        }
    }

    /// A pointroo://item/<id> link: opens the main window on that item. A link with an unsafe id does nothing.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard let id = DeepLink.itemID(from: url) else { return false }
        selectedItem = id
        return true
    }

    /// Moves an item to another project (the "Change" button). The router learns it like a picker pick.
    func reroute(_ id: String, to project: Project) -> Items.RerouteResult {
        let result = Items.reroute(id: id, to: project)
        if result == .moved { say("Sent to \(project.name)"); loadSessions() }
        return result
    }

    /// "Use another port": the next free port, then the listener and the agent install follow it.
    func useAnotherPort() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = MCPPort.useAnother()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch result {
                    case .success(let port): self.say("Agents now use port \(port)")
                    case .failure(let error): self.say(error.message)
                    }
                }
            }
        }
    }

    func open(_ row: SessionRow) { NSWorkspace.shared.open(row.dir) }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func showToast(_ s: String) { say(s) }

    private func say(_ s: String) {
        toast = s
        Task { try? await Task.sleep(nanoseconds: 2_000_000_000); if toast == s { toast = nil } }
    }

    /// Called once for each item an agent finished: the item and its project name.
    var onDone: ((Item, String) -> Void)?
    /// Called after each scan with the counts and the open and working items.
    var onQueue: ((QueueCounts, [Item]) -> Void)?
    @Published var counts = QueueCounts(open: 0, working: 0, done: 0)

    /// Item status by id at the last scan; nil until the first scan, which only records.
    private var lastItemStatus: [String: String]?
    private var lastSignature: Date?
    private var lastScan = Date.distantPast
    private var scanning = false

    /// Reads every item off the main actor and says what changed. Skipped when no session or state file changed
    /// (but at least once a minute, because an item in progress can expire without any file changing).
    func pollQueue() {
        guard !scanning else { return }
        scanning = true
        let before = lastItemStatus
        let previous = lastSignature
        let stale = Date().timeIntervalSince(lastScan) > 60
        Task.detached(priority: .utility) { [weak self] in
            let owner = self
            let signature = QueueStatus.signature()
            if before != nil, !stale, signature == previous {
                await MainActor.run { owner?.scanning = false }
                return
            }
            let items = Items.all()
            let finished = QueueStatus.newlyDone(before: before ?? [:], items: items)
                .map { ($0, Router.readRoute(Paths.root.appendingPathComponent($0.session))?.project ?? "Done") }
            let counts = QueueStatus.counts(items)
            let active = items.filter { $0.status == "open" || $0.status == "in_progress" }
            let statuses = QueueStatus.statusByID(items)
            await MainActor.run {
                guard let owner else { return }
                owner.scanning = false
                owner.lastSignature = signature
                owner.lastScan = Date()
                owner.lastItemStatus = statuses
                owner.counts = counts
                owner.onQueue?(counts, active)
                for (item, project) in finished { owner.onDone?(item, project) }
            }
        }
    }

    func loadSessions() {
        let fm = FileManager.default
        let dirs = ((try? fm.contentsOfDirectory(at: Paths.root, includingPropertiesForKeys: nil)) ?? [])
            .filter(\.hasDirectoryPath).sorted { $0.lastPathComponent > $1.lastPathComponent }
        // The newest 20 with speech, and the ones without speech between them (hidden unless Settings shows them).
        var rows: [SessionRow] = []
        for row in dirs.lazy.compactMap({ dir -> SessionRow? in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("events.json")),
                  let e = try? JSONDecoder.iso.decode(SessionEvents.self, from: data) else { return nil }
            var title = "No speech"
            if let w = try? Data(contentsOf: dir.appendingPathComponent("transcript.json")),
               let words = try? JSONDecoder().decode([Word].self, from: w), !words.isEmpty {
                title = words.prefix(9).map(\.text).joined(separator: " ")
            } else if self.phase == .processing {
                title = "Processing…"
            }
            let item = Items.items(in: dir, state: Items.readState(dir)).items.first
            return SessionRow(dir: dir, date: e.started, duration: Int(e.duration.rounded()), points: e.points.count,
                              title: title, status: item?.status ?? "", by: item?.by, note: item?.note,
                              noSpeech: title == "No speech")
        }) {
            rows.append(row)
            if rows.filter({ !$0.noSpeech }).count == 20 { break }
        }
        sessions = rows
    }
}
