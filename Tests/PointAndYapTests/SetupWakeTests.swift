import XCTest
@testable import PointAndYap

final class SetupWakeTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var folder: URL!
    private var support: URL!
    private var sessions: URL!

    override class func setUp() { _ = PointAndYapTests.root }

    override func setUpWithError() throws {
        suiteName = "SetupWakeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("setup-wake-\(UUID().uuidString)")
        support = folder.appendingPathComponent("support")
        sessions = folder.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeBridge(projects: [Project] = [], items: [Item] = [], action: ((String) -> Void)? = nil) -> WebBridge {
        WebBridge(defaults: defaults, loadItems: { items },
                  findProject: { text in projects.first { $0.name == text } },
                  loadProjects: { projects }, loadLive: { [] },
                  loadSetup: { [["id": "applications", "state": "done"]] },
                  runSetupAction: action, supportFolder: support, sessionsFolder: sessions)
    }

    private func result(_ bridge: WebBridge, _ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        let reply = try T1Support.replyObject(bridge.handle(message: ["id": 1, "method": method, "params": params]))
        return try XCTUnwrap(reply["result"] as? [String: Any])
    }

    private func code(_ bridge: WebBridge, _ method: String, _ params: [String: Any]) throws -> String? {
        try T1Support.errorCode(bridge.handle(message: ["id": 1, "method": method, "params": params]))
    }

    private func inputs(_ change: (inout SetupInputs) -> Void = { _ in }) -> SetupInputs {
        var value = SetupInputs(inApplications: true, microphone: true, screenRecording: true, accessibility: true,
                                claudeFound: true, toolAdded: true, stopHookAdded: true, speech: .ready)
        change(&value)
        return value
    }

    private func row(_ id: String, in rows: [[String: Any]]) -> [String: Any]? {
        rows.first { $0["id"] as? String == id }
    }

    private func session(_ pid: Int, socket: String?, name: String) -> String {
        let socketText = socket.map { #","messagingSocketPath":"\#($0)""# } ?? ""
        return #"{"pid":\#(pid),"sessionId":"s\#(pid)","name":"\#(name)"\#(socketText)}"#
    }

    func testSetupRowsAreAllDoneWhenEverythingIsReady() {
        let rows = SetupStatus.rows(inputs())
        XCTAssertEqual(rows.map { $0["id"] as? String },
                       ["applications", "microphone", "screenRecording", "accessibility", "claudeCode", "tool", "stopHook", "speech"])
        XCTAssertTrue(rows.allSatisfy { $0["state"] as? String == "done" })
        XCTAssertTrue(rows.allSatisfy { $0["action"] == nil })
    }

    func testSetupRowsGiveEachMissingThingItsAction() {
        let rows = SetupStatus.rows(inputs {
            $0.inApplications = false; $0.microphone = false; $0.claudeFound = false
            $0.toolAdded = false; $0.stopHookAdded = false
        })
        XCTAssertEqual(row("applications", in: rows)?["action"] as? String, "move")
        XCTAssertEqual(row("microphone", in: rows)?["action"] as? String, "allowMicrophone")
        XCTAssertEqual(row("claudeCode", in: rows)?["action"] as? String, "install")
        XCTAssertEqual(row("tool", in: rows)?["action"] as? String, "connect")
        XCTAssertEqual(row("stopHook", in: rows)?["action"] as? String, "addHook")
        XCTAssertEqual(row("screenRecording", in: rows)?["state"] as? String, "done")
    }

    func testADeniedPermissionOpensSystemSettings() {
        let rows = SetupStatus.rows(inputs { $0.microphone = false; $0.denied = ["microphone"] })
        let microphone = row("microphone", in: rows)
        XCTAssertEqual(microphone?["detail"] as? String, "denied")
        XCTAssertEqual(microphone?["action"] as? String, "openMicrophoneSettings")
        XCTAssertTrue(SetupStatus.actions.contains("openMicrophoneSettings"))
    }

    func testTheSpeechRowFollowsTheDownload() {
        XCTAssertEqual(row("speech", in: SetupStatus.rows(inputs { $0.speech = .downloading }))?["state"] as? String, "busy")
        XCTAssertEqual(row("speech", in: SetupStatus.rows(inputs { $0.speech = .checking }))?["state"] as? String, "busy")
        let failed = row("speech", in: SetupStatus.rows(inputs { $0.speech = .failed }))
        XCTAssertEqual(failed?["state"] as? String, "todo")
        XCTAssertEqual(failed?["detail"] as? String, "failed")
        XCTAssertEqual(failed?["action"] as? String, "retrySpeech")
    }

    func testTheWakeRowNeedsASessionAndASocket() {
        let old = ClaudeSessionEntry(pid: 1, sessionId: "a", hostSessionId: nil, name: nil, messagingSocketPath: nil, status: nil)
        let new = ClaudeSessionEntry(pid: 2, sessionId: "b", hostSessionId: nil, name: nil, messagingSocketPath: "/tmp/x.sock", status: nil)
        XCTAssertNil(row("wake", in: SetupStatus.rows(inputs())))
        XCTAssertEqual(row("wake", in: SetupStatus.rows(inputs { $0.sessions = [old] }))?["action"] as? String, "updateClaude")
        XCTAssertEqual(row("wake", in: SetupStatus.rows(inputs { $0.sessions = [old, new] }))?["state"] as? String, "done")
    }

    func testTheSpeechGateKeepsAndReportsItsState() {
        let gate = Transcriber.PrewarmGate()
        XCTAssertEqual(gate.state, .checking)
        let seen = Seen()
        gate.onChange = { seen.add($0) }
        gate.set(.downloading)
        gate.set(.downloading)
        gate.set(.failed)
        XCTAssertEqual(gate.state, .failed)
        XCTAssertEqual(seen.values, [.downloading, .failed])
        XCTAssertTrue(gate.claim("en-US"))
        XCTAssertFalse(gate.claim("en-US"))
        gate.release("en-US")
        XCTAssertTrue(gate.claim("en-US"))
    }

    func testTheStopHookIsFoundInSettings() throws {
        let file = folder.appendingPathComponent("settings.json")
        XCTAssertFalse(AgentInstall.hasStopHook(settings: file))
        try #"{"theme":"dark"}"#.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertFalse(AgentInstall.hasStopHook(settings: file))
        let merged = try XCTUnwrap(AgentInstall.mergingStopHook(into: ["theme": "dark"]))
        try JSONSerialization.data(withJSONObject: merged).write(to: file)
        XCTAssertTrue(AgentInstall.hasStopHook(settings: file))
    }

    func testSetupStatusReturnsTheRows() throws {
        let out = try result(makeBridge(), "setup.status")
        XCTAssertEqual((out["rows"] as? [[String: Any]])?.count, 1)
    }

    func testSetupActionRunsAKnownIdAndReturnsTheRows() throws {
        let ran = Seen()
        let bridge = makeBridge(action: { ran.add($0) })
        let out = try result(bridge, "setup.action", ["id": "addHook"])
        XCTAssertEqual(ran.ids, ["addHook"])
        XCTAssertNotNil(out["rows"])
        XCTAssertEqual(try code(bridge, "setup.action", ["id": "format-disk"]), "bad_params")
        XCTAssertEqual(try code(bridge, "setup.action", [:]), "bad_params")
        XCTAssertEqual(try code(makeBridge(),"setup.action", ["id": "addHook"]), "not_available")
    }

    func testSetupChangedIsSentOnlyWhenARowChanged() {
        var events = WebEvents()
        let first: [[String: Any]] = [["id": "speech", "state": "busy"]]
        XCTAssertEqual(events.setup(first).map(\.name), ["setup.changed"])
        XCTAssertTrue(events.setup(first).isEmpty)
        XCTAssertEqual(events.setup([["id": "speech", "state": "done"]]).count, 1)
    }

    func testWakeGetListsProjectsSessionsAndTheSwitch() throws {
        try session(1, socket: "/tmp/a.sock", name: "Pointroo lead").write(to: sessions.appendingPathComponent("1.json"), atomically: true, encoding: .utf8)
        try session(2, socket: nil, name: "Old one").write(to: sessions.appendingPathComponent("2.json"), atomically: true, encoding: .utf8)
        try #"{"Pointroo":"s1"}"#.write(to: support.appendingPathComponent("owners.json"), atomically: true, encoding: .utf8)
        let projects = [Project(name: "Pointroo", path: "/w/pointroo"), Project(name: "Tinkeroo", path: "/w/tinkeroo")]
        let out = try result(makeBridge(projects: projects), "wake.get")
        XCTAssertEqual(out["enabled"] as? Bool, true)
        let owners = try XCTUnwrap(out["owners"] as? [[String: Any]])
        XCTAssertEqual(owners.map { $0["project"] as? String }, ["Pointroo", "Tinkeroo"])
        XCTAssertEqual(owners.map { $0["owner"] as? String }, ["s1", "auto"])
        let found = try XCTUnwrap(out["sessions"] as? [[String: Any]])
        XCTAssertEqual(found.map { $0["name"] as? String }, ["Pointroo lead"])
        XCTAssertNil(out["last"])
    }

    func testWakeSetWritesTheSwitchAndOwnersAtomically() throws {
        let projects = [Project(name: "Pointroo", path: "/w/pointroo"), Project(name: "Tinkeroo", path: "/w/tinkeroo")]
        let file = support.appendingPathComponent("owners.json")
        try #"{"tinkeroo":"old"}"#.write(to: file, atomically: true, encoding: .utf8)
        let bridge = makeBridge(projects: projects)
        let out = try result(bridge, "wake.set", ["enabled": false, "owners": [["project": "Pointroo", "owner": "s1"], ["project": "Tinkeroo", "owner": "auto"]]])
        XCTAssertEqual(out["enabled"] as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "wakeSessions") as? Bool, false)
        let saved = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: file))
        XCTAssertEqual(saved, ["Pointroo": "s1"])
        let backup = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: support.appendingPathComponent("owners.json.bak")))
        XCTAssertEqual(backup, ["tinkeroo": "old"])
        _ = try result(bridge, "wake.set", ["owners": [["project": "Pointroo", "owner": "s2"]]])
        let again = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: support.appendingPathComponent("owners.json.bak")))
        XCTAssertEqual(again, ["tinkeroo": "old"])
    }

    func testWakeSetRefusesBadInput() throws {
        let bridge = makeBridge(projects: [Project(name: "Pointroo", path: "/w/pointroo")])
        XCTAssertEqual(try code(bridge, "wake.set", ["enabled": "yes"]), "bad_params")
        XCTAssertEqual(try code(bridge, "wake.set", ["owners": "x"]), "bad_params")
        XCTAssertEqual(try code(bridge, "wake.set", ["owners": [["project": "Pointroo"]]]), "bad_params")
        XCTAssertEqual(try code(bridge, "wake.set", ["owners": [["project": "Nothing", "owner": "s1"]]]), "not_found")
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("owners.json").path))
    }

    func testAnItemCarriesItsWakeRecord() throws {
        var woken = Item(id: "s#1", session: "s", n: 1, title: "t", body: "b", crops: [], status: "open", at: nil)
        woken.wake = WakeRecord(project: "Pointroo", target: "s1", name: "Pointroo lead", pid: 1, at: Date(), result: "sent")
        let out = WebBridge.dictionary(woken)
        let wake = try XCTUnwrap(out["wake"] as? [String: Any])
        XCTAssertEqual(wake["result"] as? String, "sent")
        XCTAssertEqual(wake["name"] as? String, "Pointroo lead")
        let plain = Item(id: "s#2", session: "s", n: 2, title: "t", body: "b", crops: [], status: "open", at: nil)
        XCTAssertNil(WebBridge.dictionary(plain)["wake"])
    }

    func testTheLastSentWakeShowsInWakeGet() throws {
        var woken = Item(id: "s#1", session: "s", n: 1, title: "t", body: "b", crops: [], status: "open", at: nil)
        woken.wake = WakeRecord(project: "Pointroo", target: "s1", name: "Pointroo lead", pid: 1, at: Date(), result: "sent")
        let out = try result(makeBridge(items: [woken]), "wake.get")
        let last = try XCTUnwrap(out["last"] as? [String: Any])
        XCTAssertEqual(last["project"] as? String, "Pointroo")
        XCTAssertEqual(last["name"] as? String, "Pointroo lead")
    }

    func testANewWakeRecordChangesTheItemsSignature() {
        var events = WebEvents()
        var item = Item(id: "s#1", session: "s", n: 1, title: "t", body: "b", crops: [], status: "open", at: nil)
        XCTAssertEqual(events.items([item]).count, 1)
        XCTAssertTrue(events.items([item]).isEmpty)
        item.wake = WakeRecord(project: "P", target: nil, name: nil, pid: nil, at: Date(), result: "no owner")
        XCTAssertEqual(events.items([item]).count, 1)
    }

    func testHintsCarryTheMockupWordsAndAnActionOnRetry() {
        XCTAssertEqual(Hint.noSession.message, "Not sent: no Claude session open.")
        XCTAssertEqual(Hint.speechFailed.message, "Speech download failed.")
        XCTAssertEqual(Hint.speechFailed.actionLabel, "Retry")
        XCTAssertEqual(Hint.speechFailed.action, "retrySpeech")
        XCTAssertTrue(SetupStatus.actions.contains("retrySpeech"))
        let moved = Hint.portMoved(from: 6742, to: 6743)
        XCTAssertEqual(moved.message, "Port 6742 was busy, Pointroo moved to 6743.")
        XCTAssertEqual(moved.tone, "muted")
        XCTAssertEqual(WebHost.hintEvent(moved).name, "hint.show")
    }

    @MainActor
    func testTheNoSessionHintOnlyFiresWithNothingToPickAndNobodyListening() {
        let project = Project(name: "P", path: "/w/p")
        let live = LiveSession(pid: 1, cwd: "/w/p", agent: "Claude Code", started: Date(), lastSeen: Date())
        XCTAssertTrue(AppState.shouldHintNoSession(choices: [], listening: []))
        XCTAssertFalse(AppState.shouldHintNoSession(choices: [project], listening: []))
        XCTAssertFalse(AppState.shouldHintNoSession(choices: [], listening: [live]))
    }
}

private final class Seen: @unchecked Sendable {
    private(set) var values: [SpeechState] = []
    private(set) var ids: [String] = []
    func add(_ state: SpeechState) { values.append(state) }
    func add(_ id: String) { ids.append(id) }
}
