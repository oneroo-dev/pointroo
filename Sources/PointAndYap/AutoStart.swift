import Foundation

/// A1: when an item is routed to a project folder and no agent session listens there, start ONE headless `claude -p` run in
/// that folder (only when the setting autoStartAgent is "claude"). The pure parts are here (the settings, the decision, the
/// arguments, the log trimming) so tests can cover them. AutoStartRunner does the waiting and the real process.
enum AutoStart {
    /// How long to wait after routing before looking again: a session may pick the item up by itself.
    static let waitSeconds: TimeInterval = 20
    /// The log keeps this many lines, the newest ones.
    static let logLimit = 1000

    static let agents = ["off", "claude"]
    static let models = ["sonnet", "opus", "fable"]
    static let efforts = ["low", "medium", "high", "xhigh", "max"]
    /// bypassPermissions is not offered, on purpose.
    static let permissions = ["acceptEdits", "dontAsk", "auto"]
    static let budgetRange: ClosedRange<Double> = 0.5...20

    static let defaultAgent = "off"
    static let defaultModel = "sonnet"
    static let defaultEffort = "medium"
    static let defaultBudget = 2.0
    static let defaultPermission = "acceptEdits"

    /// get_open_items also hands out items not routed anywhere, so the prompt keeps the run to this folder's items.
    static let prompt = "Work through Pointroo for this folder: call get_open_items, do each item routed to this project, then mark_done with a one-line note; use release_items for anything you cannot do and for items with no project."

    /// The five settings. A value that is not allowed becomes the default, so a bad saved value can never reach the command line.
    struct Options: Equatable {
        var agent: String
        var model: String
        var effort: String
        var budget: Double
        var permission: String

        init(agent: String = AutoStart.defaultAgent, model: String = AutoStart.defaultModel,
             effort: String = AutoStart.defaultEffort, budget: Double = AutoStart.defaultBudget,
             permission: String = AutoStart.defaultPermission) {
            self.agent = AutoStart.agents.contains(agent) ? agent : AutoStart.defaultAgent
            self.model = AutoStart.models.contains(model) ? model : AutoStart.defaultModel
            self.effort = AutoStart.efforts.contains(effort) ? effort : AutoStart.defaultEffort
            self.budget = budget.isFinite ? min(max(budget, AutoStart.budgetRange.lowerBound), AutoStart.budgetRange.upperBound) : AutoStart.defaultBudget
            self.permission = AutoStart.permissions.contains(permission) ? permission : AutoStart.defaultPermission
        }

        var enabled: Bool { agent == "claude" }

        /// What is saved now (the keys are the ones the Settings screen writes through WebBridge).
        static func current(defaults: UserDefaults = .standard) -> Options {
            Options(agent: defaults.string(forKey: "autoStartAgent") ?? AutoStart.defaultAgent,
                    model: defaults.string(forKey: "autoStartModel") ?? AutoStart.defaultModel,
                    effort: defaults.string(forKey: "autoStartEffort") ?? AutoStart.defaultEffort,
                    budget: defaults.object(forKey: "autoStartBudget") as? Double ?? AutoStart.defaultBudget,
                    permission: defaults.string(forKey: "autoStartPermission") ?? AutoStart.defaultPermission)
        }
    }

    enum Decision: Equatable {
        case wait
        case start
        case skip(String)
    }

    /// What to do for a folder an item was routed to. `secondsSinceRouted` counts from the moment of routing.
    static func decide(options: Options, liveSessionExists: Bool, runGoing: Bool, secondsSinceRouted: TimeInterval) -> Decision {
        if !options.enabled { return .skip("auto-start is off") }
        if liveSessionExists { return .skip("a session is listening") }
        if runGoing { return .skip("a run is already going") }
        if secondsSinceRouted < waitSeconds { return .wait }
        return .start
    }

    /// True when one of the sessions runs in the folder, or in a folder inside it, or above it (the same idea the router uses).
    static func hasLiveSession(in folder: String, sessions: [LiveSession]) -> Bool {
        sessions.contains { Router.related($0.cwd, folder) }
    }

    /// The command line for `claude`. The budget is always there, and so is a permission mode that is never bypassPermissions.
    static func arguments(options: Options, prompt: String = AutoStart.prompt) -> [String] {
        ["-p", prompt,
         "--model", options.model,
         "--effort", options.effort,
         "--max-budget-usd", budgetText(options.budget),
         "--permission-mode", options.permission,
         "--output-format", "json"]
    }

    /// 2 -> "2", 0.5 -> "0.5", 2.25 -> "2.25" (always a dot, never a comma).
    static func budgetText(_ budget: Double) -> String {
        String(format: "%g", budget)
    }

    /// The same folder in two spellings (a symlink, a trailing slash) is one folder.
    static func key(for folder: String) -> String {
        URL(fileURLWithPath: folder).resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// The last `limit` lines of the log text, with a closing newline. Text that is short enough is returned as it is.
    static func trimmed(_ text: String, keeping limit: Int = AutoStart.logLimit) -> String {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        guard lines.count > limit else { return text }
        return lines.suffix(limit).joined(separator: "\n") + "\n"
    }

    /// The cost in dollars from the json `claude -p --output-format json` prints (one object, or a list that ends with the result).
    static func cost(fromOutput output: String) -> Double? {
        guard let data = output.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var object = json as? [String: Any]
        if let list = json as? [[String: Any]] { object = list.last { $0["type"] as? String == "result" } ?? list.last }
        guard let object else { return nil }
        return (object["total_cost_usd"] as? Double) ?? (object["cost_usd"] as? Double)
    }

    /// A run that is going: the folder and when it started.
    struct Run: Equatable {
        var project: String
        var startedAt: Date

        var dictionary: [String: Any] {
            ["project": project, "startedAt": ISO8601DateFormatter().string(from: startedAt)]
        }
    }

    /// The last run that ended: the folder, when it ended, the exit code (-1 when it could not start) and the cost when the output had one.
    struct LastRun: Equatable {
        var project: String
        var endedAt: Date
        var exitCode: Int32
        var cost: Double?

        var dictionary: [String: Any] {
            var result: [String: Any] = ["project": project, "endedAt": ISO8601DateFormatter().string(from: endedAt), "exitCode": Int(exitCode)]
            if let cost { result["cost"] = cost }
            return result
        }
    }

    static let shared = AutoStartRunner()

    static var logFile: URL { Paths.support.appendingPathComponent("autostart.log") }

    private static let logLock = NSLock()

    /// Adds one line (with the time) to autostart.log and keeps only the newest 1000 lines.
    static func appendLog(_ message: String, to file: URL = AutoStart.logFile, now: Date = Date()) {
        logLock.lock()
        defer { logLock.unlock() }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let line = "\(ISO8601DateFormatter().string(from: now)) \(message)\n"
        let text = trimmed(existing + (existing.isEmpty || existing.hasSuffix("\n") ? "" : "\n") + line)
        do { try text.write(to: file, atomically: true, encoding: .utf8) }
        catch { FileHandle.standardError.write(Data("pointroo: could not save \(file.path): \(error.localizedDescription)\n".utf8)) }
    }

    /// The real process starter: runs the CLI in the folder, collects what it prints, and calls `completion` once when it ends.
    /// It returns a stopper for the run: terminate() asks the process to end (SIGTERM), kill() ends it for sure (SIGKILL) if it still runs.
    static func startProcess(_ request: AutoStartRunner.Request, completion: @escaping @Sendable (AutoStartRunner.Outcome) -> Void) throws -> AutoStartRunner.Stopper {
        let process = Foundation.Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: request.folder)
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = environment
        let pipe = Pipe()
        let buffer = OutputBuffer()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { buffer.append(data) }
        }
        process.terminationHandler = { finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            buffer.append(pipe.fileHandleForReading.readDataToEndOfFile())
            completion(AutoStartRunner.Outcome(exitCode: finished.terminationStatus, output: buffer.text))
        }
        try process.run()
        let box = ProcessBox(process)
        return AutoStartRunner.Stopper(
            terminate: { box.process.terminate() },
            kill: {
                if box.process.isRunning { Darwin.kill(box.process.processIdentifier, SIGKILL) }
            })
    }

    /// Holds the process so the stopper closures can be Sendable. The Process is only asked to stop, from any thread, which it allows.
    private final class ProcessBox: @unchecked Sendable {
        let process: Foundation.Process

        init(_ process: Foundation.Process) { self.process = process }
    }

    /// The output of a run, kept up to about a megabyte.
    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ more: Data) {
            lock.lock()
            defer { lock.unlock() }
            if data.count < 1_000_000 { data.append(more) }
        }

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }
    }
}

/// Waits after a route, checks again, and starts at most one run per folder. Everything it touches from the outside is
/// given to the initializer, so tests start no real process and wait no real seconds.
final class AutoStartRunner: @unchecked Sendable {
    struct Request: Equatable {
        var executable: URL
        var arguments: [String]
        var folder: String
    }

    struct Outcome: Equatable {
        var exitCode: Int32
        var output: String
    }

    /// How to end a run that is going. terminate() is the polite stop (SIGTERM); kill() is the hard one (SIGKILL), only if it still runs.
    struct Stopper: Sendable {
        var terminate: @Sendable () -> Void
        var kill: @Sendable () -> Void
    }

    /// Seconds between the polite stop and the hard kill.
    static let killDelaySeconds: TimeInterval = 5

    typealias Starter = (Request, @escaping @Sendable (Outcome) -> Void) throws -> Stopper
    typealias Scheduler = (TimeInterval, @escaping @Sendable () -> Void) -> Void

    private let options: () -> AutoStart.Options
    private let findCLI: () -> URL?
    private let liveSessionExists: (String) -> Bool
    private let hasOpenItems: (String) -> Bool
    private let start: Starter
    private let schedule: Scheduler
    private let now: () -> Date
    private let log: (String) -> Void
    private let onChange: () -> Void

    private let lock = NSLock()
    private var lastFinished: AutoStart.LastRun?
    private var waiting: [String: Date] = [:]
    private var going: [String: Date] = [:]
    /// One id for each going run, so a late kill only hits the run it was meant for.
    private var runIDs: [String: UUID] = [:]
    private var stoppers: [String: Stopper] = [:]

    init(options: @escaping () -> AutoStart.Options = { AutoStart.Options.current() },
         findCLI: @escaping () -> URL? = { AgentInstall.claudeCLI },
         liveSessionExists: @escaping (String) -> Bool = { AutoStart.hasLiveSession(in: $0, sessions: LiveSessions.all()) },
         hasOpenItems: @escaping (String) -> Bool = { folder in
             Items.all().contains { $0.status == "open" && $0.project.map { Router.samePath($0, folder) } == true }
         },
         start: @escaping Starter = { try AutoStart.startProcess($0, completion: $1) },
         schedule: @escaping Scheduler = { seconds, work in DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + seconds, execute: work) },
         now: @escaping () -> Date = { Date() },
         log: @escaping (String) -> Void = { AutoStart.appendLog($0) },
         onChange: @escaping () -> Void = {}) {
        self.options = options
        self.findCLI = findCLI
        self.liveSessionExists = liveSessionExists
        self.hasOpenItems = hasOpenItems
        self.start = start
        self.schedule = schedule
        self.now = now
        self.log = log
        self.onChange = onChange
    }

    /// The last run that ended (status.get shows it), or nil when none ended yet in this app run.
    var lastRun: AutoStart.LastRun? {
        lock.lock()
        defer { lock.unlock() }
        return lastFinished
    }

    /// The runs that are going now, oldest first (status.get shows them).
    var runs: [AutoStart.Run] {
        lock.lock()
        defer { lock.unlock() }
        return going.map { AutoStart.Run(project: $0.key, startedAt: $0.value) }.sorted { $0.startedAt < $1.startedAt }
    }

    /// An item was routed to `folder`. Does nothing when the setting is off, or when this folder is already waiting or running.
    func routed(folder: String) {
        guard options().enabled else { return }
        let key = AutoStart.key(for: folder)
        lock.lock()
        if going[key] != nil || waiting[key] != nil {
            lock.unlock()
            return
        }
        waiting[key] = now()
        lock.unlock()
        schedule(AutoStart.waitSeconds) { [self] in check(folder: folder) }
    }

    private func check(folder: String) {
        let key = AutoStart.key(for: folder)
        lock.lock()
        let routedAt = waiting[key]
        let runGoing = going[key] != nil
        lock.unlock()
        guard let routedAt else { return }
        let elapsed = now().timeIntervalSince(routedAt)
        let current = options()
        switch AutoStart.decide(options: current, liveSessionExists: liveSessionExists(folder), runGoing: runGoing, secondsSinceRouted: elapsed) {
        case .wait:
            schedule(max(AutoStart.waitSeconds - elapsed, 1)) { [self] in check(folder: folder) }
        case .skip(let reason):
            stopWaiting(key)
            log("skipped \(folder): \(reason)")
        case .start:
            guard hasOpenItems(folder) else {
                stopWaiting(key)
                log("skipped \(folder): no open items")
                return
            }
            guard let cli = findCLI() else {
                stopWaiting(key)
                log("nothing started for \(folder): the claude CLI was not found")
                return
            }
            guard let runID = claim(key) else {
                log("skipped \(folder): a run is already going")
                return
            }
            let request = Request(executable: cli, arguments: AutoStart.arguments(options: current), folder: folder)
            log("start \(folder): model \(current.model), effort \(current.effort), budget \(AutoStart.budgetText(current.budget)), permission \(current.permission)")
            do {
                let stopper = try start(request) { [self] outcome in finish(folder: folder, outcome: outcome) }
                keep(stopper, for: key, runID: runID)
                onChange()
            } catch {
                release(key)
                record(folder: folder, exitCode: -1, cost: nil)
                log("could not start \(folder): \(error.localizedDescription)")
                onChange()
            }
        }
    }

    private func stopWaiting(_ key: String) {
        lock.lock()
        waiting[key] = nil
        lock.unlock()
    }

    /// Moves the folder from waiting to going. Gives the id of the new run, or nil when a run is already going there.
    private func claim(_ key: String) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        waiting[key] = nil
        if going[key] != nil { return nil }
        going[key] = now()
        let runID = UUID()
        runIDs[key] = runID
        return runID
    }

    private func release(_ key: String) {
        lock.lock()
        going[key] = nil
        runIDs[key] = nil
        stoppers[key] = nil
        lock.unlock()
    }

    /// Keeps the stopper, but only when this run is still the one going (it may have ended already, very fast).
    private func keep(_ stopper: Stopper, for key: String, runID: UUID) {
        lock.lock()
        if runIDs[key] == runID { stoppers[key] = stopper }
        lock.unlock()
    }

    /// Ends the run going in `project` (SIGTERM now, SIGKILL after 5 seconds if it is still the same run). False when no run is going there.
    /// The normal finish path then frees the folder and records the last run, as for any run that ends.
    @discardableResult
    func stop(project: String) -> Bool {
        let key = AutoStart.key(for: project)
        lock.lock()
        guard going[key] != nil, let stopper = stoppers[key], let runID = runIDs[key] else {
            lock.unlock()
            return false
        }
        lock.unlock()
        log("stopped by user \(project)")
        stopper.terminate()
        schedule(Self.killDelaySeconds) { [self] in
            lock.lock()
            let sameRun = runIDs[key] == runID
            lock.unlock()
            if sameRun { stopper.kill() }
        }
        return true
    }

    /// For when the app quits: ends every going run now, so no headless claude stays behind. There is no time to wait 5 seconds at
    /// quit, so each run gets terminate() and then kill() straight away (kill does nothing when the process is already gone).
    func stopAll() {
        lock.lock()
        let entries = going.keys.compactMap { key in stoppers[key].map { (key, $0) } }
        lock.unlock()
        for (key, stopper) in entries {
            log("stopped at quit \(key)")
            stopper.terminate()
            stopper.kill()
        }
    }

    private func finish(folder: String, outcome: Outcome) {
        release(AutoStart.key(for: folder))
        let cost = AutoStart.cost(fromOutput: outcome.output)
        record(folder: folder, exitCode: outcome.exitCode, cost: cost)
        let costText = cost.map { ", cost $\(String(format: "%.4f", $0))" } ?? ""
        log("end \(folder): exit \(outcome.exitCode)\(costText)")
        onChange()
    }

    private func record(folder: String, exitCode: Int32, cost: Double?) {
        let entry = AutoStart.LastRun(project: AutoStart.key(for: folder), endedAt: now(), exitCode: exitCode, cost: cost)
        lock.lock()
        lastFinished = entry
        lock.unlock()
    }
}
