import XCTest
@testable import PointAndYap

/// A1: auto-start of a headless Claude run. The decision, the command line, the settings, the log and the one-run-per-folder
/// rule are tested without starting a real process or waiting a real second.
final class AutoStartTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override class func setUp() { _ = PointAndYapTests.root }

    override func setUp() {
        suiteName = "AutoStartTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private let on = AutoStart.Options(agent: "claude")

    func testDecideSkipsWhenTheSettingIsOff() {
        let decision = AutoStart.decide(options: AutoStart.Options(), liveSessionExists: false, runGoing: false, secondsSinceRouted: 60)
        XCTAssertEqual(decision, .skip("auto-start is off"))
    }

    func testDecideSkipsWhenASessionIsListening() {
        let decision = AutoStart.decide(options: on, liveSessionExists: true, runGoing: false, secondsSinceRouted: 60)
        XCTAssertEqual(decision, .skip("a session is listening"))
    }

    func testDecideSkipsWhenARunIsAlreadyGoing() {
        let decision = AutoStart.decide(options: on, liveSessionExists: false, runGoing: true, secondsSinceRouted: 60)
        XCTAssertEqual(decision, .skip("a run is already going"))
    }

    func testDecideWaitsUnderTwentySeconds() {
        XCTAssertEqual(AutoStart.decide(options: on, liveSessionExists: false, runGoing: false, secondsSinceRouted: 0), .wait)
        XCTAssertEqual(AutoStart.decide(options: on, liveSessionExists: false, runGoing: false, secondsSinceRouted: 19.9), .wait)
    }

    func testDecideStartsAtTwentySecondsAndLater() {
        XCTAssertEqual(AutoStart.decide(options: on, liveSessionExists: false, runGoing: false, secondsSinceRouted: 20), .start)
        XCTAssertEqual(AutoStart.decide(options: on, liveSessionExists: false, runGoing: false, secondsSinceRouted: 300), .start)
    }

    func testALiveSessionInsideOrAboveTheFolderCountsAsListening() {
        func session(_ cwd: String) -> LiveSession {
            LiveSession(pid: 1, cwd: cwd, agent: "claude", started: Date(), lastSeen: Date())
        }
        XCTAssertTrue(AutoStart.hasLiveSession(in: "/work/shop", sessions: [session("/work/shop")]))
        XCTAssertTrue(AutoStart.hasLiveSession(in: "/work/shop", sessions: [session("/work/shop/api")]))
        XCTAssertTrue(AutoStart.hasLiveSession(in: "/work/shop/api", sessions: [session("/work/shop")]))
        XCTAssertFalse(AutoStart.hasLiveSession(in: "/work/shop", sessions: [session("/work/shop-app")]))
        XCTAssertFalse(AutoStart.hasLiveSession(in: "/work/shop", sessions: []))
    }

    func testTheDefaultArgumentsAreSonnetMediumTwoDollarsAcceptEdits() {
        XCTAssertEqual(AutoStart.arguments(options: AutoStart.Options(agent: "claude")),
                       ["-p", AutoStart.prompt, "--model", "sonnet", "--effort", "medium", "--max-budget-usd", "2",
                        "--permission-mode", "acceptEdits", "--output-format", "json"])
    }

    func testEachSettingGoesIntoItsOwnArgument() {
        let options = AutoStart.Options(agent: "claude", model: "opus", effort: "xhigh", budget: 7.5, permission: "dontAsk")
        XCTAssertEqual(AutoStart.arguments(options: options, prompt: "go"),
                       ["-p", "go", "--model", "opus", "--effort", "xhigh", "--max-budget-usd", "7.5",
                        "--permission-mode", "dontAsk", "--output-format", "json"])
        for model in AutoStart.models {
            let arguments = AutoStart.arguments(options: AutoStart.Options(agent: "claude", model: model))
            XCTAssertEqual(arguments[arguments.firstIndex(of: "--model")! + 1], model)
        }
        for effort in AutoStart.efforts {
            let arguments = AutoStart.arguments(options: AutoStart.Options(agent: "claude", effort: effort))
            XCTAssertEqual(arguments[arguments.firstIndex(of: "--effort")! + 1], effort)
        }
        for permission in AutoStart.permissions {
            let arguments = AutoStart.arguments(options: AutoStart.Options(agent: "claude", permission: permission))
            XCTAssertEqual(arguments[arguments.firstIndex(of: "--permission-mode")! + 1], permission)
        }
    }

    func testTheBudgetIsAlwaysThereEvenForBadValues() throws {
        for budget in [0, -3, 500, Double.nan, Double.infinity, 0.5, 20] {
            let arguments = AutoStart.arguments(options: AutoStart.Options(agent: "claude", budget: budget))
            let index = try XCTUnwrap(arguments.firstIndex(of: "--max-budget-usd"))
            let value = try XCTUnwrap(Double(arguments[index + 1]))
            XCTAssertTrue(AutoStart.budgetRange.contains(value), "\(budget) gave \(value)")
        }
    }

    func testBypassPermissionsNeverReachesTheCommandLine() {
        for bad in ["bypassPermissions", "manual", "plan", "", "ACCEPTEDITS"] {
            let options = AutoStart.Options(agent: "claude", permission: bad)
            XCTAssertEqual(options.permission, "acceptEdits", bad)
            XCTAssertFalse(AutoStart.arguments(options: options).contains("bypassPermissions"))
        }
        XCTAssertFalse(AutoStart.permissions.contains("bypassPermissions"))
    }

    func testBadSettingsBecomeTheDefaults() {
        let options = AutoStart.Options(agent: "codex", model: "gpt", effort: "ultra", budget: .nan, permission: "x")
        XCTAssertEqual(options, AutoStart.Options())
        XCTAssertFalse(options.enabled)
    }

    func testOptionsAreReadFromTheSavedSettings() {
        XCTAssertEqual(AutoStart.Options.current(defaults: defaults), AutoStart.Options())
        defaults.set("claude", forKey: "autoStartAgent")
        defaults.set("fable", forKey: "autoStartModel")
        defaults.set("max", forKey: "autoStartEffort")
        defaults.set(12.0, forKey: "autoStartBudget")
        defaults.set("auto", forKey: "autoStartPermission")
        XCTAssertEqual(AutoStart.Options.current(defaults: defaults),
                       AutoStart.Options(agent: "claude", model: "fable", effort: "max", budget: 12, permission: "auto"))
    }

    func testBudgetTextHasADotAndNoNeedlessZeros() {
        XCTAssertEqual(AutoStart.budgetText(2), "2")
        XCTAssertEqual(AutoStart.budgetText(0.5), "0.5")
        XCTAssertEqual(AutoStart.budgetText(2.25), "2.25")
        XCTAssertEqual(AutoStart.budgetText(20), "20")
    }

    func testTheCostIsReadFromTheJsonResult() {
        XCTAssertEqual(AutoStart.cost(fromOutput: #"{"type":"result","total_cost_usd":0.1234,"result":"ok"}"#), 0.1234)
        XCTAssertEqual(AutoStart.cost(fromOutput: #"[{"type":"system"},{"type":"result","total_cost_usd":1.5}]"#), 1.5)
        XCTAssertNil(AutoStart.cost(fromOutput: #"{"type":"result"}"#))
        XCTAssertNil(AutoStart.cost(fromOutput: "not json"))
        XCTAssertNil(AutoStart.cost(fromOutput: ""))
    }

    func testTheLogKeepsTheNewestThousandLines() {
        let text = (1...1500).map { "line \($0)" }.joined(separator: "\n") + "\n"
        let trimmed = AutoStart.trimmed(text)
        let lines = trimmed.components(separatedBy: "\n").dropLast()
        XCTAssertEqual(lines.count, 1000)
        XCTAssertEqual(lines.first, "line 501")
        XCTAssertEqual(lines.last, "line 1500")
        XCTAssertTrue(trimmed.hasSuffix("\n"))
    }

    func testAShortLogIsLeftAsItIs() {
        XCTAssertEqual(AutoStart.trimmed("a\nb\n"), "a\nb\n")
        XCTAssertEqual(AutoStart.trimmed(""), "")
        let exact = (1...1000).map { "l\($0)" }.joined(separator: "\n") + "\n"
        XCTAssertEqual(AutoStart.trimmed(exact), exact)
    }

    func testAppendLogWritesALineWithTheTimeAndKeepsTheFileShort() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("autostart-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("autostart.log")
        for number in 1...1005 { AutoStart.appendLog("message \(number)", to: file, now: Date(timeIntervalSince1970: 0)) }
        let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n").dropLast()
        XCTAssertEqual(lines.count, 1000)
        XCTAssertEqual(lines.first, "1970-01-01T00:00:00Z message 6")
        XCTAssertEqual(lines.last, "1970-01-01T00:00:00Z message 1005")
    }

    private func bridge() -> WebBridge {
        WebBridge(defaults: defaults, loadStatus: {
            AppStatus(mcpRunning: false, mcpPort: 1, mcpText: "", sessions: 0, agents: [],
                      microphone: false, screenRecording: false, accessibility: false)
        })
    }

    private func code(_ subject: WebBridge, _ params: [String: Any]) throws -> String? {
        try T1Support.errorCode(subject.handle(message: ["id": 1, "method": "settings.set", "params": params]))
    }

    private func set(_ subject: WebBridge, _ key: String, _ value: Any) throws -> [String: Any] {
        let reply = try T1Support.replyObject(subject.handle(message: ["id": 1, "method": "settings.set", "params": ["key": key, "value": value]]))
        return try XCTUnwrap(reply["result"] as? [String: Any], "\(reply)")
    }

    func testTheFiveSettingsAreAllowedWithTheirDefaults() throws {
        let reply = try T1Support.replyObject(bridge().handle(message: ["id": 1, "method": "settings.get", "params": [:] as [String: Any]]))
        let values = try XCTUnwrap((reply["result"] as? [String: Any])?["values"] as? [String: Any])
        XCTAssertEqual(values["autoStartAgent"] as? String, "off")
        XCTAssertEqual(values["autoStartModel"] as? String, "sonnet")
        XCTAssertEqual(values["autoStartEffort"] as? String, "medium")
        XCTAssertEqual(values["autoStartBudget"] as? Double, 2)
        XCTAssertEqual(values["autoStartPermission"] as? String, "acceptEdits")
    }

    func testTheChoiceSettingsTakeOnlyTheirKnownValues() throws {
        let subject = bridge()
        let good: [String: [String]] = ["autoStartAgent": AutoStart.agents, "autoStartModel": AutoStart.models,
                                        "autoStartEffort": AutoStart.efforts, "autoStartPermission": AutoStart.permissions]
        for (key, values) in good {
            for value in values { XCTAssertEqual(try set(subject, key, value)["value"] as? String, value) }
            for bad in ["bypassPermissions", "", "Claude", " claude", "codex", 5, true, NSNull(), ["claude"]] as [Any] {
                XCTAssertEqual(try code(subject, ["key": key, "value": bad]), "bad_params", "\(key) \(bad)")
            }
            XCTAssertEqual(try code(subject, ["key": key]), "bad_params", "\(key) with no value")
        }
        XCTAssertEqual(defaults.string(forKey: "autoStartPermission"), "auto", "the last good value stays")
    }

    func testTheBudgetTakesOnlyANumberFromHalfADollarToTwenty() throws {
        let subject = bridge()
        XCTAssertEqual(try set(subject, "autoStartBudget", 5)["value"] as? Double, 5)
        XCTAssertEqual(try set(subject, "autoStartBudget", 0.5)["value"] as? Double, 0.5)
        XCTAssertEqual(try set(subject, "autoStartBudget", 20)["value"] as? Double, 20)
        for bad in [0.49, 0, -1, 20.01, 1000, Double.nan, Double.infinity, "5", true, false, NSNull(), [5]] as [Any] {
            XCTAssertEqual(try code(subject, ["key": "autoStartBudget", "value": bad]), "bad_params", "\(bad)")
        }
        XCTAssertEqual(defaults.double(forKey: "autoStartBudget"), 20, "the last good value stays")
    }

    func testStatusDictionaryHasTheAutoRuns() {
        let started = Date(timeIntervalSince1970: 0)
        var status = AppStatus(mcpRunning: false, mcpPort: 1, mcpText: "", sessions: 0, agents: [],
                               microphone: false, screenRecording: false, accessibility: false)
        XCTAssertEqual((status.dictionary["autoRuns"] as? [[String: Any]])?.count, 0)
        status.autoRuns = [AutoStart.Run(project: "/work/shop", startedAt: started)]
        let runs = status.dictionary["autoRuns"] as? [[String: Any]]
        XCTAssertEqual(runs?.count, 1)
        XCTAssertEqual(runs?.first?["project"] as? String, "/work/shop")
        XCTAssertEqual(runs?.first?["startedAt"] as? String, "1970-01-01T00:00:00Z")
    }

    private final class Harness: @unchecked Sendable {
        var options = AutoStart.Options(agent: "claude")
        var cli: URL? = URL(fileURLWithPath: "/fake/bin/claude")
        var liveSession = false
        var openItems = true
        var folderExists = true
        var startError: Error?
        var clock = Date(timeIntervalSince1970: 1000)
        var started: [AutoStartRunner.Request] = []
        var finishers: [@Sendable (AutoStartRunner.Outcome) -> Void] = []
        var scheduled: [(seconds: TimeInterval, work: @Sendable () -> Void)] = []
        var logs: [String] = []
        var changeCount = 0
        /// One entry per started run, in order: how many times its stopper was asked to terminate and to kill.
        var terminateCounts: [Int] = []
        var killCounts: [Int] = []

        lazy var runner = AutoStartRunner(
            options: { self.options },
            findCLI: { self.cli },
            liveSessionExists: { _ in self.liveSession },
            hasOpenItems: { _ in self.openItems },
            start: { request, finish in
                if let error = self.startError { throw error }
                self.started.append(request)
                self.finishers.append(finish)
                let index = self.terminateCounts.count
                self.terminateCounts.append(0)
                self.killCounts.append(0)
                return AutoStartRunner.Stopper(terminate: { self.terminateCounts[index] += 1 },
                                               kill: { self.killCounts[index] += 1 })
            },
            schedule: { seconds, work in self.scheduled.append((seconds, work)) },
            now: { self.clock },
            log: { self.logs.append($0) },
            onChange: { self.changeCount += 1 },
            folderExists: { _ in self.folderExists })

        /// Lets the waiting time pass and runs what was scheduled.
        func letTimePass(_ seconds: TimeInterval = 20) {
            clock = clock.addingTimeInterval(seconds)
            let due = scheduled
            scheduled = []
            for entry in due { entry.work() }
        }
    }

    func testNothingIsScheduledOrStartedWhileTheSettingIsOff() {
        let harness = Harness()
        harness.options = AutoStart.Options()
        harness.runner.routed(folder: "/work/shop")
        XCTAssertTrue(harness.scheduled.isEmpty)
        harness.letTimePass()
        XCTAssertTrue(harness.started.isEmpty)
        XCTAssertTrue(harness.runner.runs.isEmpty)
    }

    func testARouteWaitsTwentySecondsThenStartsOneRunInTheFolder() throws {
        let harness = Harness()
        harness.runner.routed(folder: "/work/shop")
        XCTAssertEqual(harness.scheduled.count, 1)
        XCTAssertEqual(harness.scheduled.first?.seconds, 20)
        XCTAssertTrue(harness.started.isEmpty, "nothing starts before the wait is over")
        harness.letTimePass()
        let request = try XCTUnwrap(harness.started.first)
        XCTAssertEqual(harness.started.count, 1)
        XCTAssertEqual(request.executable.path, "/fake/bin/claude")
        XCTAssertEqual(request.folder, "/work/shop")
        XCTAssertEqual(request.arguments, AutoStart.arguments(options: harness.options))
        XCTAssertEqual(harness.runner.runs.map(\.project), [AutoStart.key(for: "/work/shop")])
    }

    func testASecondRouteToTheSameFolderStartsNoSecondRun() {
        let harness = Harness()
        harness.runner.routed(folder: "/work/shop")
        harness.runner.routed(folder: "/work/shop/")
        XCTAssertEqual(harness.scheduled.count, 1, "already waiting")
        harness.letTimePass()
        harness.runner.routed(folder: "/work/shop")
        harness.letTimePass()
        XCTAssertEqual(harness.started.count, 1, "a run is going")
        XCTAssertEqual(harness.runner.runs.count, 1)
    }

    func testTwoFoldersRunAtTheSameTime() {
        let harness = Harness()
        harness.runner.routed(folder: "/work/shop")
        harness.runner.routed(folder: "/work/blog")
        harness.letTimePass()
        XCTAssertEqual(harness.started.map(\.folder).sorted(), ["/work/blog", "/work/shop"])
        XCTAssertEqual(harness.runner.runs.count, 2)
    }

    func testAFinishedRunFreesTheFolderAndIsLogged() {
        let harness = Harness()
        harness.runner.routed(folder: "/work/shop")
        harness.letTimePass()
        harness.finishers[0](AutoStartRunner.Outcome(exitCode: 0, output: #"{"total_cost_usd":0.25}"#))
        XCTAssertTrue(harness.runner.runs.isEmpty)
        XCTAssertTrue(harness.logs.contains { $0.hasPrefix("end /work/shop: exit 0") && $0.contains("$0.2500") }, "\(harness.logs)")
        harness.runner.routed(folder: "/work/shop")
        harness.letTimePass()
        XCTAssertEqual(harness.started.count, 2)
    }

    func testAFinishedRunIsKeptAsTheLastRunWithItsCost() throws {
        let harness = Harness()
        XCTAssertNil(harness.runner.lastRun)
        harness.runner.routed(folder: "/work/shop")
        harness.letTimePass()
        XCTAssertNil(harness.runner.lastRun, "a run that is still going is not the last run")
        harness.clock = harness.clock.addingTimeInterval(50)
        harness.finishers[0](AutoStartRunner.Outcome(exitCode: 0, output: #"{"total_cost_usd":0.25}"#))
        let last = try XCTUnwrap(harness.runner.lastRun)
        XCTAssertEqual(last.project, AutoStart.key(for: "/work/shop"))
        XCTAssertEqual(last.endedAt, harness.clock)
        XCTAssertEqual(last.exitCode, 0)
        XCTAssertEqual(last.cost, 0.25)
    }

    func testAFinishedRunWithoutCostKeepsNoCost() throws {
        let harness = Harness()
        harness.runner.routed(folder: "/work/shop")
        harness.letTimePass()
        harness.finishers[0](AutoStartRunner.Outcome(exitCode: 2, output: "not json"))
        let last = try XCTUnwrap(harness.runner.lastRun)
        XCTAssertEqual(last.exitCode, 2)
        XCTAssertNil(last.cost)
    }

    func testARunThatCouldNotStartIsTheLastRunWithExitCodeMinusOne() throws {
        struct Boom: Error {}
        let harness = Harness()
        harness.startError = Boom()
        harness.runner.routed(folder: "/work/shop")
        harness.letTimePass()
        let last = try XCTUnwrap(harness.runner.lastRun)
        XCTAssertEqual(last.project, AutoStart.key(for: "/work/shop"))
        XCTAssertEqual(last.exitCode, -1)
        XCTAssertNil(last.cost)
        XCTAssertTrue(harness.runner.runs.isEmpty)
    }

    func testOnChangeIsCalledWhenARunStartsAndWhenItEnds() {
        let harness = Harness()
        harness.runner.routed(folder: "/work/shop")
        XCTAssertEqual(harness.changeCount, 0, "waiting changes nothing")
        harness.letTimePass()
        XCTAssertEqual(harness.changeCount, 1, "start")
        harness.finishers[0](AutoStartRunner.Outcome(exitCode: 0, output: ""))
        XCTAssertEqual(harness.changeCount, 2, "end")
    }

    func testStatusDictionaryHasTheLastAutoRunOnlyWhenPresent() {
        var status = AppStatus(mcpRunning: false, mcpPort: 1, mcpText: "", sessions: 0, agents: [],
                               microphone: false, screenRecording: false, accessibility: false)
        XCTAssertNil(status.dictionary["lastAutoRun"])
        status.lastAutoRun = AutoStart.LastRun(project: "/work/shop", endedAt: Date(timeIntervalSince1970: 0), exitCode: 1, cost: 0.5)
        var last = status.dictionary["lastAutoRun"] as? [String: Any]
        XCTAssertEqual(last?["project"] as? String, "/work/shop")
        XCTAssertEqual(last?["endedAt"] as? String, "1970-01-01T00:00:00Z")
        XCTAssertEqual(last?["exitCode"] as? Int, 1)
        XCTAssertEqual(last?["cost"] as? Double, 0.5)
        status.lastAutoRun = AutoStart.LastRun(project: "/work/shop", endedAt: Date(timeIntervalSince1970: 0), exitCode: -1, cost: nil)
        last = status.dictionary["lastAutoRun"] as? [String: Any]
        XCTAssertEqual(last?["exitCode"] as? Int, -1)
        XCTAssertNil(last?["cost"])
    }

    func testASessionThatShowsUpDuringTheWaitStopsTheRun() {
        let harness = Harness()
        harness.runner.routed(folder: "/work/shop")
        harness.liveSession = true
        harness.letTimePass()
        XCTAssertTrue(harness.started.isEmpty)
        XCTAssertTrue(harness.logs.contains { $0.contains("a session is listening") })
        harness.liveSession = false
        harness.runner.routed(folder: "/work/shop")
        XCTAssertEqual(harness.scheduled.count, 1, "the folder is free to wait again")
    }

    func testTheSettingTurnedOffDuringTheWaitStopsTheRun() {
        let harness = Harness()
        harness.runner.routed(folder: "/work/shop")
        harness.options = AutoStart.Options()
        harness.letTimePass()
        XCTAssertTrue(harness.started.isEmpty)
    }

    func testNoOpenItemsLeftMeansNoRun() {
        let harness = Harness()
        harness.runner.routed(folder: "/work/shop")
        harness.openItems = false
        harness.letTimePass()
        XCTAssertTrue(harness.started.isEmpty)
        XCTAssertTrue(harness.logs.contains { $0.contains("no open items") })
    }

    func testAMissingCLIStartsNothingAndLogsOneLine() {
        let harness = Harness()
        harness.cli = nil
        harness.runner.routed(folder: "/work/shop")
        harness.letTimePass()
        XCTAssertTrue(harness.started.isEmpty)
        XCTAssertTrue(harness.runner.runs.isEmpty)
        XCTAssertEqual(harness.logs.filter { $0.contains("claude CLI was not found") }.count, 1)
    }

    func testAProcessThatCannotStartFreesTheFolderAndIsLogged() {
        struct Boom: Error {}
        let harness = Harness()
        harness.startError = Boom()
        harness.runner.routed(folder: "/work/shop")
        harness.letTimePass()
        XCTAssertTrue(harness.runner.runs.isEmpty)
        XCTAssertTrue(harness.logs.contains { $0.hasPrefix("could not start /work/shop") })
    }

    func testTheStartLineNamesTheChosenSettings() {
        let harness = Harness()
        harness.options = AutoStart.Options(agent: "claude", model: "opus", effort: "high", budget: 4, permission: "auto")
        harness.runner.routed(folder: "/work/shop")
        harness.letTimePass()
        XCTAssertEqual(harness.logs.first, "start /work/shop: model opus, effort high, budget 4, permission auto")
    }

    func testStopOnAGoingRunTerminatesItAndLogsIt() {
        let harness = Harness()
        harness.runner.routed(folder: "/work/shop")
        harness.letTimePass()
        XCTAssertTrue(harness.runner.stop(project: "/work/shop/"))
        XCTAssertEqual(harness.terminateCounts, [1])
        XCTAssertEqual(harness.killCounts, [0], "the hard kill waits for the scheduler")
        XCTAssertTrue(harness.logs.contains("stopped by user /work/shop/"), "\(harness.logs)")
        XCTAssertEqual(harness.scheduled.last?.seconds, 5)
        XCTAssertEqual(harness.runner.runs.count, 1, "the folder is freed by the normal finish, not by stop")
        harness.finishers[0](AutoStartRunner.Outcome(exitCode: 15, output: ""))
        XCTAssertTrue(harness.runner.runs.isEmpty)
        XCTAssertEqual(harness.runner.lastRun?.exitCode, 15)
    }

    func testStopWithNoRunGoingReturnsFalseAndTerminatesNothing() {
        let harness = Harness()
        XCTAssertFalse(harness.runner.stop(project: "/work/shop"))
        harness.runner.routed(folder: "/work/shop")
        XCTAssertFalse(harness.runner.stop(project: "/work/shop"), "waiting is not going")
        harness.letTimePass()
        XCTAssertFalse(harness.runner.stop(project: "/work/blog"), "another folder")
        XCTAssertEqual(harness.terminateCounts, [0])
        XCTAssertFalse(harness.logs.contains { $0.hasPrefix("stopped") })
    }

    func testTheKillComesAfterFiveSecondsOnlyWhileTheSameRunIsGoing() {
        let harness = Harness()
        harness.runner.routed(folder: "/work/shop")
        harness.letTimePass()
        XCTAssertTrue(harness.runner.stop(project: "/work/shop"))
        harness.letTimePass(5)
        XCTAssertEqual(harness.killCounts, [1], "still running after 5 seconds, so it is killed")

        harness.finishers[0](AutoStartRunner.Outcome(exitCode: 15, output: ""))
        harness.runner.routed(folder: "/work/shop")
        harness.letTimePass()
        XCTAssertTrue(harness.runner.stop(project: "/work/shop"))
        harness.finishers[1](AutoStartRunner.Outcome(exitCode: 15, output: ""))
        harness.runner.routed(folder: "/work/shop")
        harness.scheduled.reverse()
        harness.letTimePass()
        XCTAssertEqual(harness.started.count, 3, "a new run is going in the same folder")
        XCTAssertEqual(harness.killCounts, [1, 0, 0], "the late kill for run two came after run three started and must not touch it")
    }

    func testStopAllStopsEveryRunAndLogsEach() {
        let harness = Harness()
        harness.runner.routed(folder: "/work/shop")
        harness.runner.routed(folder: "/work/blog")
        harness.letTimePass()
        harness.runner.stopAll()
        XCTAssertEqual(harness.terminateCounts, [1, 1])
        XCTAssertEqual(harness.killCounts, [1, 1], "at quit there is no 5 second wait")
        XCTAssertTrue(harness.logs.contains("stopped at quit \(AutoStart.key(for: "/work/shop"))"), "\(harness.logs)")
        XCTAssertTrue(harness.logs.contains("stopped at quit \(AutoStart.key(for: "/work/blog"))"), "\(harness.logs)")
    }

    func testStopAllWithNoRunsDoesNothing() {
        let harness = Harness()
        harness.runner.stopAll()
        XCTAssertTrue(harness.logs.isEmpty)
    }

    func testTheBridgeStopsARunThroughTheGivenClosure() throws {
        var asked: [String] = []
        let subject = WebBridge(defaults: defaults, stopAutoRun: { asked.append($0); return $0 == "/work/shop" })
        func stopped(_ params: [String: Any]) throws -> Bool? {
            let reply = try T1Support.replyObject(subject.handle(message: ["id": 1, "method": "autoRuns.stop", "params": params]))
            return (reply["result"] as? [String: Any])?["stopped"] as? Bool
        }
        XCTAssertEqual(try stopped(["project": "/work/shop"]), true)
        XCTAssertEqual(try stopped(["project": "/work/unknown"]), false)
        XCTAssertEqual(asked, ["/work/shop", "/work/unknown"])
        for bad in [[:], ["project": ""], ["project": 5], ["project": NSNull()]] as [[String: Any]] {
            XCTAssertEqual(try T1Support.errorCode(subject.handle(message: ["id": 1, "method": "autoRuns.stop", "params": bad])), "bad_params", "\(bad)")
        }
        XCTAssertEqual(asked.count, 2, "bad params never reach the closure")
    }

    func testAfterAMissingCLIALaterRouteCanTryAgain() {
        let harness = Harness()
        harness.cli = nil
        harness.runner.routed(folder: "/work/shop")
        harness.letTimePass()
        XCTAssertTrue(harness.started.isEmpty)
        XCTAssertEqual(harness.logs.count, 1, "exactly one line for the whole failed try: \(harness.logs)")
        XCTAssertNil(harness.runner.lastRun, "nothing ran, so there is no last run")
        harness.cli = URL(fileURLWithPath: "/fake/bin/claude")
        harness.runner.routed(folder: "/work/shop")
        XCTAssertEqual(harness.scheduled.count, 1, "the folder is not left waiting")
        harness.letTimePass()
        XCTAssertEqual(harness.started.count, 1)
    }

    func testARunThatExitsWithAnErrorFreesTheFolderAndALaterRouteStartsAgain() throws {
        let harness = Harness()
        harness.runner.routed(folder: "/work/shop")
        harness.letTimePass()
        harness.finishers[0](AutoStartRunner.Outcome(exitCode: 1, output: ""))
        XCTAssertTrue(harness.runner.runs.isEmpty)
        let last = try XCTUnwrap(harness.runner.lastRun)
        XCTAssertEqual(last.exitCode, 1)
        XCTAssertEqual(last.project, AutoStart.key(for: "/work/shop"))
        XCTAssertTrue(harness.logs.contains { $0.hasPrefix("end /work/shop: exit 1") }, "\(harness.logs)")
        harness.runner.routed(folder: "/work/shop")
        harness.letTimePass()
        XCTAssertEqual(harness.started.count, 2)
        XCTAssertEqual(harness.runner.runs.count, 1)
    }

    func testAStoppedRunThatEndsBeforeTheKillDelayIsNeverKilled() {
        let harness = Harness()
        harness.runner.routed(folder: "/work/shop")
        harness.letTimePass()
        XCTAssertTrue(harness.runner.stop(project: "/work/shop"))
        harness.finishers[0](AutoStartRunner.Outcome(exitCode: 15, output: ""))
        XCTAssertTrue(harness.runner.runs.isEmpty, "finish frees the folder")
        harness.letTimePass(5)
        XCTAssertEqual(harness.killCounts, [0], "the run is gone, so the late kill does nothing")
    }

    func testAFolderDeletedDuringTheWaitIsSkippedAndLogged() {
        let harness = Harness()
        harness.runner.routed(folder: "/work/shop")
        harness.folderExists = false
        harness.letTimePass()
        XCTAssertTrue(harness.started.isEmpty)
        XCTAssertTrue(harness.runner.runs.isEmpty)
        XCTAssertTrue(harness.logs.contains("skipped /work/shop: the folder is gone"), "\(harness.logs)")
        harness.folderExists = true
        harness.runner.routed(folder: "/work/shop")
        XCTAssertEqual(harness.scheduled.count, 1, "the folder is not left waiting")
        harness.letTimePass()
        XCTAssertEqual(harness.started.count, 1)
    }

    func testTheKeyMadeAtRouteTimeIsUsedAfterTheFolderIsDeleted() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("autostart-drift-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let harness = Harness()
        harness.runner.routed(folder: folder.path)
        try FileManager.default.removeItem(at: folder)
        harness.letTimePass()
        XCTAssertEqual(harness.started.count, 1, "the wait entry is still found, even if the key of the missing path would differ")
        XCTAssertEqual(harness.runner.runs.count, 1)
    }

    func testAFolderThatDoesNotExistOnDiskWorksLikeAnyOtherFolder() {
        let harness = Harness()
        harness.runner.routed(folder: "/work/never-existed/")
        XCTAssertEqual(harness.scheduled.count, 1)
        harness.letTimePass()
        XCTAssertEqual(harness.started.count, 1)
        XCTAssertEqual(harness.runner.runs.map(\.project), ["/work/never-existed"])
    }

    func testTwoRunsStoppedAtQuitAreBothLoggedAndFreedOnFinish() {
        let harness = Harness()
        harness.runner.routed(folder: "/work/shop")
        harness.runner.routed(folder: "/work/blog")
        harness.letTimePass()
        harness.runner.stopAll()
        XCTAssertEqual(harness.logs.filter { $0.hasPrefix("stopped at quit") }.count, 2)
        harness.finishers[0](AutoStartRunner.Outcome(exitCode: 15, output: ""))
        harness.finishers[1](AutoStartRunner.Outcome(exitCode: 15, output: ""))
        XCTAssertTrue(harness.runner.runs.isEmpty)
    }

    func testTheSameFolderThroughATrailingSlashOrASymlinkIsOneFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("autostart-links-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real")
        let link = root.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertEqual(AutoStart.key(for: real.path), AutoStart.key(for: link.path))
        XCTAssertEqual(AutoStart.key(for: real.path + "/"), AutoStart.key(for: real.path))

        let harness = Harness()
        harness.runner.routed(folder: real.path)
        harness.runner.routed(folder: link.path)
        harness.runner.routed(folder: real.path + "/")
        XCTAssertEqual(harness.scheduled.count, 1, "one wait for the one folder")
        harness.letTimePass()
        XCTAssertEqual(harness.started.count, 1)
        harness.runner.routed(folder: link.path)
        harness.letTimePass()
        XCTAssertEqual(harness.started.count, 1, "a run is going in that folder")
        XCTAssertEqual(harness.runner.runs.count, 1)
        XCTAssertTrue(harness.runner.stop(project: link.path), "stop finds the run through the other spelling")
        XCTAssertEqual(harness.terminateCounts, [1])
    }
}
