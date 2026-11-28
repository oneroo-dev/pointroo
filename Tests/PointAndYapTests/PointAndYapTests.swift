import XCTest
@testable import PointAndYap

/// A synthetic recording ("This button should be blue, not gray, and here, the date is wrong. It should say today.",
/// a rest on a Save button, a short pass over a group, a rest on a date label), in a temporary sessions folder.
final class PointAndYapTests: XCTestCase {
    static let root: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pointandyap-tests-\(UUID().uuidString)/sessions")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        setenv("POINTANDYAP_SESSIONS", dir.path, 1)   // read once by Paths.root
        let support = dir.deletingLastPathComponent().appendingPathComponent("support")
        setenv("POINTANDYAP_SUPPORT", support.path, 1)   // read once by Paths.support
        return dir
    }()

    /// A processed copy of the fixture under its own id.
    func session(_ id: String) -> URL {
        let src = Bundle.module.url(forResource: "Fixtures/2026-10-17_120000", withExtension: nil)!
        let dst = Self.root.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: dst)
        try! FileManager.default.copyItem(at: src, to: dst)
        let events = try! JSONDecoder.iso.decode(SessionEvents.self, from: Data(contentsOf: dst.appendingPathComponent("events.json")))
        let words = try! JSONDecoder().decode([Word].self, from: Data(contentsOf: dst.appendingPathComponent("transcript.json")))
        _ = Builder.build(dir: dst, events: events, words: words)
        return dst
    }

    /// The temporary folder is set before anything reads Paths.root, which is read once.
    override class func setUp() { _ = root }

    override func setUpWithError() throws {
        // Never run against a real sessions folder: every test stops here unless Paths.root is the temporary one.
        guard Paths.root.standardizedFileURL.path == Self.root.standardizedFileURL.path,
              Paths.root.path.hasPrefix(FileManager.default.temporaryDirectory.path) else {
            fatalError("PointAndYapTests: Paths.root is \(Paths.root.path), not the temporary folder; refusing to touch it")
        }
        for d in (try? FileManager.default.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: d)
        }
    }

    func testSentencesSplitAtPunctuationAndPauses() {
        let w = [Word(text: "This", start: 0, end: 0.2), Word(text: "works.", start: 0.2, end: 0.5),
                 Word(text: "Next", start: 0.6, end: 0.8), Word(text: "one", start: 2.0, end: 2.2)]
        XCTAssertEqual(Builder.sentences(w).map { $0.words.count }, [2, 1, 1])
    }

    func testTimelineMarksWhereTheCursorRested() throws {
        let dir = session("2026-10-17_120001")
        let md = try String(contentsOf: dir.appendingPathComponent("session.md"), encoding: .utf8)
        XCTAssertTrue(md.contains("This [1] button"), md)
        XCTAssertTrue(md.contains("here, [3] the date"), md)
        XCTAssertTrue(md.contains("AXButton \"Save\""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("crops/03.jpg").path))
    }

    func testOneRecordingIsOneItemWithItsPointsButNotCursorTravel() {
        let dir = session("2026-10-17_120002")
        let items = Items.items(in: dir, state: nil).items
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].body.contains("[1] dwell"))
        XCTAssertTrue(items[0].body.contains("[3] dwell"))
        XCTAssertFalse(items[0].body.contains("[2] dwell"), "a 0.3 s pass is cursor travel")
        XCTAssertEqual(items[0].crops.count, 2)
    }

    func testTwoAgentsNeverGetTheSameItem() {
        _ = session("2026-10-17_120003")
        _ = session("2026-10-17_120004")
        let a = Items.openItems(limit: 1, take: true, agent: "a")
        let b = Items.openItems(limit: 5, take: true, agent: "b")
        XCTAssertEqual(a.count, 1)
        XCTAssertEqual(b.count, 1)
        XCTAssertNotEqual(a[0].id, b[0].id)
        XCTAssertTrue(Items.openItems(limit: 5, take: true, agent: "c").isEmpty)
    }

    func testDoneStaysDoneAndReleasedComesBack() {
        _ = session("2026-10-17_120005")
        let id = Items.openItems(limit: 1, take: true, agent: "a")[0].id
        XCTAssertEqual(Items.set([id], status: "open", agent: "a", note: "needs the user").changed, [id])
        let again = Items.openItems(limit: 1, take: true, agent: "b")
        XCTAssertEqual(again.first?.id, id)
        XCTAssertEqual(again.first?.note, "needs the user")
        XCTAssertEqual(Items.set([id], status: "done", agent: "b", note: "fixed").changed, [id])
        XCTAssertTrue(Items.openItems(limit: 5, take: true, agent: "c").isEmpty)
        XCTAssertFalse(Items.set([id], status: "in_progress", agent: "c", note: nil).missing.isEmpty, "a done item cannot be started")
    }

    func testAnAbandonedItemReturnsAfterTheLease() throws {
        let dir = session("2026-10-17_120006")
        var st = ItemState(source: "session")
        st.items["1"] = .init(status: "in_progress", by: "a", at: Date().addingTimeInterval(-Items.lease - 60), note: nil)
        Items.writeState(st, dir)
        XCTAssertEqual(Items.items(in: dir, state: Items.readState(dir)).items.first?.status, "open")
    }

    func testIdsOutsideTheSessionsFolderAreRefused() {
        XCTAssertEqual(Items.set(["../etc#1", "nope#1"], status: "done", agent: "x", note: nil).changed, [])
        XCTAssertNil(MCPServer.dir("../etc"))
    }

    func testMCPListsAndHandsOutItems() {
        _ = session("2026-10-17_120007")
        let tools = MCPServer.tools.compactMap { $0["name"] as? String }
        for t in ["get_open_items", "mark_done", "release_items", "start_items", "list_items", "get_session"] {
            XCTAssertTrue(tools.contains(t), t)
        }
        let r = MCPServer.call("get_open_items", ["images": false])
        let text = (r["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
        XCTAssertTrue(text.contains("2026-10-17_120007#1"), text)
        XCTAssertTrue(text.contains("mark_done"))
        let done = MCPServer.call("mark_done", ["ids": ["2026-10-17_120007#1"], "note": "ok"])
        XCTAssertNil(done["isError"])
    }

    func testPointrooHasItsOwnNamesAndNeverUsesPointAndYapOnes() {
        XCTAssertEqual(AgentInstall.server, "pointroo")
        XCTAssertEqual(AgentInstall.skillName, "pointroo")
        XCTAssertEqual(AgentInstall.binary, "/Applications/Pointroo.app/Contents/MacOS/Pointroo")
        XCTAssertFalse(AgentInstall.skill.contains("point-and-yap"))
        XCTAssertFalse(Paths.support.path.contains("PointAndYap"))
    }

    func testTheCodexTableIsAddedOnceAndOtherTablesStay() {
        let toml = """
        [mcp_servers.pointandyap]
        command = "/Applications/Point and Yap.app/Contents/MacOS/PointAndYap"
        args = ["--mcp"]

        [profile]
        name = "y"
        """
        let out = AgentInstall.addingCodexTable(to: toml)
        XCTAssertTrue(out.hasPrefix(toml), "the pointandyap entry is left exactly as it was")
        XCTAssertTrue(out.contains("[mcp_servers.pointroo]") && out.contains(AgentInstall.binary))
        XCTAssertEqual(AgentInstall.addingCodexTable(to: out), out, "adding twice changes nothing")
    }

    func point(url: String? = nil, window: String? = nil) -> PointEvent {
        PointEvent(index: 0, t: 0, end: 1, at: Pt(x: 0, y: 0), kind: "dwell", app: "Safari", bundleID: nil, window: window, url: url, element: nil, frame: nil)
    }

    let projects = [Project(name: "cms", path: "/work/cms", aliases: ["content"], hosts: ["localhost:3000"]),
                    Project(name: "shop", path: "/work/shop", titles: ["Checkout admin"])]

    func testRouterSaidNameWinsAndIgnoresPunctuation() {
        XCTAssertEqual(Router.route(words: ["CMS:", "fix", "this"], points: [point(window: "shop")], projects: projects),
                       Router.Result(path: "/work/cms", how: "said"))
        XCTAssertEqual(Router.route(words: ["Content,", "page"], points: [], projects: projects)?.path, "/work/cms")
        XCTAssertNil(Router.route(words: ["fix", "this", "button", "cms"], points: [], projects: projects))
    }

    func testRouterUrlHostAndPort() {
        let result = Router.route(words: ["fix"], points: [point(url: "http://localhost:3000/posts"), point(url: "http://localhost:4000/")], projects: projects)
        XCTAssertEqual(result, Router.Result(path: "/work/cms", how: "screen"))
        XCTAssertNil(Router.route(words: ["fix"], points: [point(url: "http://localhost:4000/")], projects: projects))
        XCTAssertEqual(Router.route(words: [], points: [point(url: "https://shop.example.com/a")], projects: projects)?.path, "/work/shop")
    }

    func testRouterWindowTitle() {
        XCTAssertEqual(Router.route(words: [], points: [point(window: "Edit post - CMS")], projects: projects)?.path, "/work/cms")
        XCTAssertEqual(Router.route(words: [], points: [point(window: "Checkout admin / orders")], projects: projects)?.path, "/work/shop")
        XCTAssertNil(Router.route(words: [], points: [point(window: "cmsx tools")], projects: projects), "whole word only")
    }

    func testRouterTieGivesNothing() {
        XCTAssertNil(Router.route(words: [], points: [point(window: "cms"), point(window: "shop")], projects: projects))
    }

    func testRouterOnlyLiveSessionIsTheFallback() {
        let live = LiveSession(pid: 1, cwd: "/work/other", agent: "claude", started: Date(), lastSeen: Date())
        XCTAssertEqual(Router.route(words: ["fix"], points: [], projects: projects, live: [live]), Router.Result(path: "/work/other", how: "only"))
        let second = LiveSession(pid: 2, cwd: "/work/third", agent: "claude", started: Date(), lastSeen: Date())
        XCTAssertNil(Router.route(words: ["fix"], points: [], projects: projects, live: [live, second]))
    }

    func testOpenItemsAreFilteredByProject() {
        let own = session("2026-10-17_120010"), other = session("2026-10-17_120011"), loose = session("2026-10-17_120012")
        Router.writeRoute(RouteInfo(project: "cms", path: "/work/cms", how: "said"), to: own)
        Router.writeRoute(RouteInfo(project: "shop", path: "/work/shop", how: "said"), to: other)
        let ids = Items.openItems(limit: 10, take: false, agent: "a", project: "/work/cms/app").map(\.id)
        XCTAssertEqual(Set(ids), ["2026-10-17_120010#1", "2026-10-17_120012#1"])
        XCTAssertEqual(Items.openItems(limit: 10, take: false, agent: "a").count, 3)
        XCTAssertEqual(Items.items(in: own, state: nil).items.first?.project, "/work/cms")
        XCTAssertNil(Items.items(in: loose, state: nil).items.first?.project)
    }

    func testWaitForNextTimesOutAndListsItsTool() {
        XCTAssertTrue(MCPServer.tools.contains { $0["name"] as? String == "wait_for_next" })
        let result = MCPServer.call("wait_for_next", ["timeout_seconds": 0])
        let text = (result["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
        XCTAssertTrue(text.hasPrefix("Nothing new yet"), text)
    }

    func testHookStopBlocksOnlyWhenItemsWait() throws {
        XCTAssertNil(HookStop.output(openCount: 0))
        XCTAssertNil(HookStop.output(openCount: 3, stopHookActive: true), "no loop when the hook already blocked once")
        let line = try XCTUnwrap(HookStop.output(openCount: 2))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: String])
        XCTAssertEqual(json["decision"], "block")
        XCTAssertTrue(json["reason"]?.hasPrefix("2 new Pointroo item(s)") == true)
    }

    func testLiveSessionsSkipDeadProcessesAndKnownProjectsMerge() throws {
        LiveSessions.register(cwd: "/work/live-one", agent: "claude")
        LiveSessions.register(cwd: "/work/ghost", agent: "claude", pid: 2_000_000_000)
        let live = LiveSessions.all()
        XCTAssertEqual(live.map(\.cwd), ["/work/live-one"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: LiveSessions.file(2_000_000_000).path), "dead pid file is deleted")
        let known = Projects.known(file: projects + [Project(name: "x", path: "/work/live-one")], live: live, claude: [], owners: [:])
        XCTAssertEqual(known.filter { $0.path == "/work/live-one" }.count, 1)
        XCTAssertEqual(Projects.known(file: projects, live: live, claude: [], owners: [:]).last?.name, "live-one")
        LiveSessions.unregister()
        XCTAssertTrue(LiveSessions.all().isEmpty)
    }

    func testUnroutedItemsAreOnlyForAnExplicitGetOpenItems() {
        let own = session("2026-10-17_120020"), loose = session("2026-10-17_120021")
        Router.writeRoute(RouteInfo(project: "cms", path: "/work/cms", how: "said"), to: own)
        let waiting = Items.openItems(limit: 10, take: false, agent: "a", project: "/work/cms", unrouted: .never).map(\.id)
        XCTAssertEqual(waiting, ["2026-10-17_120020#1"], "wait_for_next and the hook never get an unrouted item")
        XCTAssertEqual(Items.openItems(limit: 10, take: false, agent: "a", project: "/work/cms").count, 2, "explicit get_open_items keeps own + unrouted")
        _ = loose
    }

    func testListeningOnlyGetsRecordingsMadeAfterItStartedOrRoutedOnPurpose() {
        let said = session("2026-10-17_120040"), fallback = session("2026-10-17_120041"), fresh = session("2026-10-17_120042")
        Router.writeRoute(RouteInfo(project: "cms", path: "/work/cms", how: "said"), to: said)
        Router.writeRoute(RouteInfo(project: "cms", path: "/work/cms", how: "only"), to: fallback)
        let started = Items.recordedAt("2026-10-17_120041")!.addingTimeInterval(0.5)
        func ids(_ date: Date) -> Set<String> {
            Set(Items.openItems(limit: 10, take: false, agent: "a", project: "/work/cms", unrouted: .never, since: date).map(\.id))
        }
        XCTAssertEqual(ids(started), ["2026-10-17_120040#1"], "old and said: yes; old and only: no")
        Router.writeRoute(RouteInfo(project: "cms", path: "/work/cms", how: "only"), to: fresh)
        XCTAssertEqual(ids(started), ["2026-10-17_120040#1", "2026-10-17_120042#1"], "a new recording routed as only is fine")
    }

    func testFollowUpGoesToTheProjectOfTheLastAgentItemWithinThreeMinutes() {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let live = [LiveSession(pid: 1, cwd: "/work/shop", agent: "claude", started: started, lastSeen: started),
                    LiveSession(pid: 2, cwd: "/work/cms", agent: "claude", started: started, lastSeen: started)]
        func done(_ secondsBefore: Double) -> (path: String, id: String, at: Date) {
            ("/work/shop", "s#1", started.addingTimeInterval(-secondsBefore))
        }
        XCTAssertEqual(Router.followUp(lastDone: done(60), recordingStarted: started, live: live)?.path, "/work/shop")
        XCTAssertEqual(Router.followUp(lastDone: done(60), recordingStarted: started, live: live)?.id, "s#1")
        XCTAssertNotNil(Router.followUp(lastDone: done(180), recordingStarted: started, live: live), "180 s is still inside")
        XCTAssertNil(Router.followUp(lastDone: done(181), recordingStarted: started, live: live))
        XCTAssertNil(Router.followUp(lastDone: nil, recordingStarted: started, live: live))
        XCTAssertNil(Router.followUp(lastDone: done(60), recordingStarted: started, live: [live[1]]), "no live session in that project")
        XCTAssertNil(Router.followUp(lastDone: done(-5), recordingStarted: started, live: live), "finished after the recording began")
    }

    func testRouteOrderIsSaidScreenFollowUpOnlyPicker() {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let live = [LiveSession(pid: 1, cwd: "/work/shop", agent: "claude", started: started, lastSeen: started),
                    LiveSession(pid: 2, cwd: "/work/cms", agent: "claude", started: started, lastSeen: started)]
        let last = (path: "/work/shop", id: "s#1", at: started.addingTimeInterval(-30))
        let both = live
        func route(words: [String] = ["fix"], points: [PointEvent] = [], running: [LiveSession]? = nil) -> Router.Result? {
            Router.route(words: words, points: points, projects: projects, live: running ?? both, lastDone: last, recordingStarted: started)
        }
        XCTAssertEqual(route(), Router.Result(path: "/work/shop", how: "followup", follows: "s#1"))
        XCTAssertEqual(route(words: ["cms", "fix"])?.how, "said", "a said name wins")
        XCTAssertEqual(route(words: ["cms", "fix"])?.path, "/work/cms")
        XCTAssertEqual(route(points: [point(window: "Edit post - CMS")])?.how, "screen", "the screen wins")
        XCTAssertEqual(route(running: [both[1]])?.how, "only", "no live session in the done project: fall through to only")
        XCTAssertEqual(route(running: [both[1]])?.path, "/work/cms")
        XCTAssertNil(Router.route(words: ["fix"], points: [], projects: projects, live: live), "nothing done lately: the picker")
    }

    func testRouteInfoWithoutFollowsStillDecodesAndFollowUpSkipsTheSinceRule() throws {
        let old = Data(#"{"project":"cms","path":"/work/cms","how":"said"}"#.utf8)
        let info = try JSONDecoder().decode(RouteInfo.self, from: old)
        XCTAssertNil(info.follows)
        let dir = session("2026-10-17_120050")
        Router.writeRoute(RouteInfo(project: "cms", path: "/work/cms", how: "followup", follows: "x#1"), to: dir)
        let after = Items.recordedAt("2026-10-17_120050")!.addingTimeInterval(60)
        let ids = Items.openItems(limit: 10, take: false, agent: "a", project: "/work/cms", unrouted: .never, since: after).map(\.id)
        XCTAssertEqual(ids, ["2026-10-17_120050#1"], "a follow-up is routed on purpose")
    }

    func testItemBodyQuotesTheFollowedItemsNote() {
        let first = session("2026-10-17_120060"), second = session("2026-10-17_120061")
        _ = Items.set(["2026-10-17_120060#1"], status: "done", agent: "claude", note: "Changed the button to blue")
        Router.writeRoute(RouteInfo(project: "cms", path: "/work/cms", how: "followup", follows: "2026-10-17_120060#1"), to: second)
        let body = Items.items(in: second, state: nil).items.first?.body ?? ""
        XCTAssertTrue(body.contains("Follow-up to 2026-10-17_120060#1. The agent that finished it wrote (quoted): \"Changed the button to blue\""), body)
        XCTAssertFalse((Items.items(in: first, state: Items.readState(first)).items.first?.body ?? "").contains("Follow-up to"))
    }

    func testSaidNameAcceptsLooseSpeech() {
        let all = projects + [Project(name: "pointroo", path: "/work/pointroo"), Project(name: "oneroo", path: "/work/oneroo")]
        XCTAssertEqual(Router.saidProject(["Pintro,", "this", "is", "a", "test"], all)?.path, "/work/pointroo")
        XCTAssertEqual(Router.saidProject(["point", "roo", "fix"], all)?.path, "/work/pointroo")
        XCTAssertEqual(Router.saidProject(["Pointroo:", "x"], all)?.path, "/work/pointroo")
        XCTAssertEqual(Router.saidProject(["oneroo", "fix"], all)?.path, "/work/oneroo", "oneroo is not pointroo")
        XCTAssertNil(Router.saidProject([".2,", "this", "is", "a", "test"], all))
        XCTAssertNil(Router.saidProject(["cm", "fix"], all), "short names match exactly only")
        XCTAssertNil(Router.saidProject(["shot", "fix"], [Project(name: "shipping", path: "/a")]))
    }

    func testSaidNameDistanceGrowsWithNameLength() {
        let pointroo = [Project(name: "pointroo", path: "/work/pointroo")]
        XCTAssertEqual(Router.saidProject(["Point", "true,", "this", "is", "a", "test"], pointroo)?.path, "/work/pointroo")
        XCTAssertNil(Router.saidProject(["oneroo", "fix"], pointroo), "distance 3 with another first letter")
        XCTAssertNil(Router.saidProject(["point", "fix"], pointroo), "too short a part of the name")
        let both = pointroo + [Project(name: "oneroo", path: "/work/oneroo")]
        XCTAssertEqual(Router.saidProject(["one", "roo", "fix"], both)?.path, "/work/oneroo")
    }

    func testLearnSavesOnlyDevelopmentHosts() {
        let directory = Self.root.appendingPathComponent("learn-hosts")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let events = SessionEvents(started: Date(), duration: 1, samples: [],
                                   points: [point(url: "https://claude.ai/chat/1"), point(url: "http://localhost:5173/app")], frames: [])
        try! JSONEncoder.pretty.encode(events).write(to: directory.appendingPathComponent("events.json"))
        Projects.save([])
        Projects.learn(from: directory, project: Project(name: "learnme", path: "/work/learnme"))
        XCTAssertEqual(Projects.load().first { $0.path == "/work/learnme" }?.hosts, ["localhost:5173"])
        XCTAssertTrue(Router.isDevelopmentHost("::1:3000"))
        XCTAssertTrue(Router.isDevelopmentHost("shop.test"))
        XCTAssertFalse(Router.isDevelopmentHost("github.com"))
    }

    func testTwoProjectsEquallyCloseGiveNoSaidMatch() {
        let both = [Project(name: "pointra", path: "/a"), Project(name: "pointro", path: "/b")]
        XCTAssertNil(Router.saidProject(["pointrx"], both))
        XCTAssertEqual(Router.saidProject(["pointro"], both)?.path, "/b", "an exact match beats a close one")
    }

    func testWaitTimeoutStaysUnderTheClientLimit() {
        XCTAssertEqual(MCPServer.defaultWait, 50)
        XCTAssertEqual(MCPServer.waitTimeout(1800), 55)
        XCTAssertEqual(MCPServer.waitTimeout(-5), 0)
    }

    func testAnItemIsNotReportedChangedWhenItsStateCannotBeSaved() throws {
        let dir = session("2026-10-17_120030")
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        guard !fm.isWritableFile(atPath: dir.path) else { throw XCTSkip("folder is writable anyway (running as root)") }
        let result = Items.set(["2026-10-17_120030#1"], status: "done", agent: "a", note: nil)
        XCTAssertTrue(result.changed.isEmpty)
        XCTAssertTrue(result.missing.first?.contains("could not save state") == true, "\(result.missing)")
        XCTAssertTrue(Items.openItems(limit: 5, take: true, agent: "a").isEmpty, "not taken when the state cannot be saved")
    }
}
