import XCTest
@testable import PointAndYap

/// R24: a suggested project for a recording that was not sent, the recent order of projects, and sending to the only
/// listening session without the picker.
final class SuggestTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override class func setUp() { _ = PointAndYapTests.root }

    override func setUp() {
        suiteName = "SuggestTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private let known = [Project(name: "pointroo", path: "/work/pointroo"), Project(name: "shop", path: "/work/shop-app")]

    private func point(url: String? = nil, window: String? = nil) -> PointEvent {
        PointEvent(index: 0, t: 0, end: 1, at: Pt(x: 0, y: 0), kind: "dwell", app: "Safari", bundleID: nil,
                   window: window, url: url, element: nil, frame: nil)
    }

    private func live(_ cwd: String, pid: Int32 = 1) -> LiveSession {
        LiveSession(pid: pid, cwd: cwd, agent: "claude", started: Date(), lastSeen: Date())
    }

    private func makeSession(_ id: String) throws -> URL {
        let source = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/2026-10-17_120000", withExtension: nil))
        let target = PointAndYapTests.root.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)
        let events = try JSONDecoder.iso.decode(SessionEvents.self, from: Data(contentsOf: target.appendingPathComponent("events.json")))
        let words = try JSONDecoder().decode([Word].self, from: Data(contentsOf: target.appendingPathComponent("transcript.json")))
        _ = Builder.build(dir: target, events: events, words: words)
        try? FileManager.default.removeItem(at: Router.routeURL(target))
        try? FileManager.default.removeItem(at: Router.suggestURL(target))
        addTeardownBlock { try? FileManager.default.removeItem(at: target) }
        return target
    }

    private func events(points: [PointEvent] = []) -> SessionEvents {
        SessionEvents(started: Date(), duration: 3, samples: [], points: points, frames: [])
    }

    private let words = [Word(text: "fix", start: 0, end: 1), Word(text: "this", start: 1, end: 2)]

    func testSuggestUsesAWindowTitleThatRouteIsNotSureAbout() {
        let points = [point(window: "pointrooapp docs - Safari")]
        XCTAssertNil(Router.route(words: ["fix"], points: points, projects: known))
        let result = Router.suggest(words: ["fix"], points: points, projects: known)
        XCTAssertEqual(result, Router.Result(path: "/work/pointroo", how: "related"))
    }

    func testSuggestUsesAHostAndTheFolderName() {
        let byHost = Router.suggest(words: [], points: [point(url: "https://pointroo-staging.example.com/a")], projects: known)
        XCTAssertEqual(byHost?.path, "/work/pointroo")
        let byFolder = Router.suggest(words: [], points: [point(window: "shop-app admin")], projects: known)
        XCTAssertEqual(byFolder?.path, "/work/shop-app", "the folder name counts even when the project name differs")
    }

    func testSuggestIgnoresShortNamesAndTiesOnTheScreen() {
        let short = [Project(name: "cms", path: "/work/cms")]
        XCTAssertNil(Router.suggest(words: [], points: [point(window: "cmsx tools")], projects: short))
        let tie = Router.suggest(words: [], points: [point(window: "pointrooapp"), point(window: "shop-app")], projects: known)
        XCTAssertNil(tie)
    }

    func testSuggestFallsBackToTheLastSentProjectWithinThirtyMinutes() {
        let now = Date()
        let recent = Router.suggest(words: [], points: [], projects: known, lastSent: (path: "/work/shop-app", at: now.addingTimeInterval(-29 * 60)), now: now)
        XCTAssertEqual(recent, Router.Result(path: "/work/shop-app", how: "lastsent"))
        let old = Router.suggest(words: [], points: [], projects: known, lastSent: (path: "/work/shop-app", at: now.addingTimeInterval(-31 * 60)), now: now)
        XCTAssertNil(old)
        let future = Router.suggest(words: [], points: [], projects: known, lastSent: (path: "/work/shop-app", at: now.addingTimeInterval(60)), now: now)
        XCTAssertNil(future)
    }

    func testSuggestFallsBackToTheOnlyListeningProject() {
        let one = Router.suggest(words: [], points: [], projects: known, live: [live("/work/solo", pid: 1), live("/work/solo", pid: 2)])
        XCTAssertEqual(one, Router.Result(path: "/work/solo", how: "only"))
        XCTAssertNil(Router.suggest(words: [], points: [], projects: known, live: [live("/work/a"), live("/work/b", pid: 2)]))
        XCTAssertNil(Router.suggest(words: [], points: [], projects: known, live: []))
    }

    func testSuggestOrderIsScreenThenLastSentThenOnlyListening() {
        let now = Date()
        let lastSent = (path: "/work/shop-app", at: now.addingTimeInterval(-60))
        let sessions = [live("/work/solo")]
        let all = Router.suggest(words: [], points: [point(window: "pointrooapp docs")], projects: known, live: sessions, lastSent: lastSent, now: now)
        XCTAssertEqual(all?.how, "related")
        XCTAssertEqual(all?.path, "/work/pointroo")
        let noScreen = Router.suggest(words: [], points: [], projects: known, live: sessions, lastSent: lastSent, now: now)
        XCTAssertEqual(noScreen?.how, "lastsent")
        let onlyLive = Router.suggest(words: [], points: [], projects: known, live: sessions, lastSent: nil, now: now)
        XCTAssertEqual(onlyLive?.how, "only")
    }

    func testLastSentIsTheNewestRecordingThatHasARoute() {
        func routed(_ session: String, _ path: String?, how: String? = "said") -> Item {
            var item = Item(id: "\(session)#1", session: session, n: 1, title: "t", body: "", crops: [], status: "open", at: nil)
            item.project = path
            item.routeHow = how
            return item
        }
        let items = [routed("2026-11-24_100000", "/work/a"), routed("2026-11-24_110000", "/work/b"),
                     routed("2026-11-24_120000", nil, how: nil)]
        let found = Router.lastSent(items)
        XCTAssertEqual(found?.path, "/work/b")
        XCTAssertEqual(found?.at, Items.recordedAt("2026-11-24_110000"))
        XCTAssertNil(Router.lastSent([routed("2026-11-24_120000", nil, how: nil)]))
    }

    func testRouteSessionWritesSuggestJsonWhenNothingRoutes() throws {
        let directory = try makeSession("r24-suggest-a")
        let items = [Item(id: "r24-old#1", session: "r24-old", n: 1, title: "t", body: "", crops: [], status: "open", at: nil)]
        Router.routeSession(directory, events: events(points: [point(window: "pointrooapp docs")]), words: words,
                            live: [live("/work/a"), live("/work/b", pid: 2)], knownProjects: known, items: items,
                            autoSendSingle: true, now: Date())
        XCTAssertNil(Router.readRoute(directory))
        XCTAssertEqual(Router.readSuggest(directory), SuggestInfo(path: "/work/pointroo", how: "related"))
        let item = try XCTUnwrap(Items.items(in: directory, state: nil).items.first)
        XCTAssertEqual(item.suggested, "/work/pointroo")
        XCTAssertNil(item.project)
    }

    func testRouteSessionWritesNoSuggestWhenThereIsNoGuess() throws {
        let directory = try makeSession("r24-suggest-b")
        Router.routeSession(directory, events: events(), words: words, live: [live("/work/a"), live("/work/b", pid: 2)],
                            knownProjects: known, items: [], autoSendSingle: true, now: Date())
        XCTAssertNil(Router.readSuggest(directory))
        XCTAssertNil(Items.items(in: directory, state: nil).items.first?.suggested)
    }

    func testALaterRouteRemovesSuggestJson() throws {
        let directory = try makeSession("r24-suggest-c")
        Router.writeSuggest(SuggestInfo(path: "/work/pointroo", how: "related"), to: directory)
        XCTAssertNotNil(Router.readSuggest(directory))
        Router.writeRoute(RouteInfo(project: "shop", path: "/work/shop-app", how: "picked"), to: directory)
        XCTAssertNil(Router.readSuggest(directory), "a pick or reroute removes the suggestion")
        XCTAssertNil(Items.items(in: directory, state: nil).items.first?.suggested)
    }

    func testRouteSessionThatRoutesRemovesAnOldSuggestion() throws {
        let directory = try makeSession("r24-suggest-d")
        Router.writeSuggest(SuggestInfo(path: "/work/shop-app", how: "lastsent"), to: directory)
        Router.routeSession(directory, events: events(), words: [Word(text: "pointroo", start: 0, end: 1)],
                            live: [], knownProjects: known, items: [], autoSendSingle: true, now: Date())
        XCTAssertEqual(Router.readRoute(directory)?.path, "/work/pointroo")
        XCTAssertNil(Router.readSuggest(directory))
    }

    func testUnrouteKeepsTheProjectAsASuggestion() throws {
        let directory = try makeSession("r24-suggest-g")
        Router.writeRoute(RouteInfo(project: "shop", path: "/work/shop-app", how: "only"), to: directory)
        XCTAssertEqual(Items.unroute(id: "r24-suggest-g#1"), .unrouted)
        XCTAssertNil(Router.readRoute(directory))
        XCTAssertEqual(Router.readSuggest(directory), SuggestInfo(path: "/work/shop-app", how: "undone"))
        let item = try XCTUnwrap(Items.items(in: directory, state: nil).items.first)
        XCTAssertNil(item.project)
        XCTAssertEqual(item.suggested, "/work/shop-app")
    }

    func testAutoSendDecisionIsPure() {
        let only = Router.Result(path: "/work/solo", how: "only")
        XCTAssertTrue(Router.shouldAutoSend(only, autoSendSingle: true))
        XCTAssertFalse(Router.shouldAutoSend(only, autoSendSingle: false))
        for how in ["said", "screen", "followup"] {
            XCTAssertTrue(Router.shouldAutoSend(Router.Result(path: "/work/x", how: how), autoSendSingle: false), "\(how) never needs the setting")
        }
    }

    func testRouteSessionSendsToTheOnlySessionWhenAutoSendIsOn() throws {
        let directory = try makeSession("r24-suggest-e")
        Router.routeSession(directory, events: events(), words: words, live: [live("/work/solo")],
                            knownProjects: known, items: [], autoSendSingle: true, now: Date())
        XCTAssertEqual(Router.readRoute(directory)?.how, "only")
        XCTAssertEqual(Router.readRoute(directory)?.path, "/work/solo")
        XCTAssertNil(Router.readSuggest(directory))
    }

    func testRouteSessionKeepsTheOnlySessionAsASuggestionWhenAutoSendIsOff() throws {
        let directory = try makeSession("r24-suggest-f")
        Router.routeSession(directory, events: events(), words: words, live: [live("/work/solo")],
                            knownProjects: known, items: [], autoSendSingle: false, now: Date())
        XCTAssertNil(Router.readRoute(directory))
        XCTAssertEqual(Router.readSuggest(directory), SuggestInfo(path: "/work/solo", how: "only"))
    }

    func testBridgeSendsSuggestedAndItsName() {
        var item = Item(id: "s#1", session: "s", n: 1, title: "t", body: "", crops: [], status: "open", at: nil)
        XCTAssertNil(WebBridge.dictionary(item)["suggested"])
        item.suggested = "/work/pointroo"
        let out = WebBridge.dictionary(item)
        XCTAssertEqual(out["suggested"] as? String, "/work/pointroo")
        XCTAssertEqual(out["suggestedName"] as? String, "pointroo")
    }

    func testAutoSendSingleSettingIsOnUntilTurnedOff() throws {
        let subject = WebBridge(defaults: defaults)
        func value() throws -> Bool? {
            let script = subject.handle(message: ["id": 1, "method": "settings.get", "params": ["key": "autoSendSingle"]])
            return try replyResult(script)["value"] as? Bool
        }
        XCTAssertEqual(try value(), true)
        _ = subject.handle(message: ["id": 2, "method": "settings.set", "params": ["key": "autoSendSingle", "value": false]])
        XCTAssertEqual(try value(), false)
    }

    private func replyResult(_ script: String) throws -> [String: Any] {
        let prefix = "window.pointroo.reply("
        let inner = String(script.dropFirst(prefix.count).dropLast())
        let split = try XCTUnwrap(inner.range(of: ", {"))
        let json = "{" + inner[split.upperBound...]
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        return try XCTUnwrap(object["result"] as? [String: Any])
    }

    private let projectList = [Project(name: "zeta", path: "/work/zeta"), Project(name: "Alpha", path: "/work/alpha"),
                               Project(name: "beta", path: "/work/beta"), Project(name: "gamma", path: "/work/gamma")]

    private func routedItem(_ id: String, project: String, at: Date?) -> Item {
        var item = Item(id: id, session: "s", n: 1, title: "t", body: "", crops: [], status: "open", at: at)
        item.project = project
        return item
    }

    private func projectEntries(items: [Item], sessions: [LiveSession] = []) throws -> [[String: Any]] {
        let list = projectList
        let subject = WebBridge(defaults: defaults, loadItems: { items }, loadProjects: { list }, loadLive: { sessions })
        let script = subject.handle(message: ["id": 1, "method": "projects.list", "params": [:]])
        return try XCTUnwrap(replyResult(script)["projects"] as? [[String: Any]])
    }

    func testProjectsListGivesLastUsedAndOrdersTheNotListeningOnesByIt() throws {
        let newer = Date(timeIntervalSince1970: 1_700_100_000), older = Date(timeIntervalSince1970: 1_700_000_000)
        let items = [routedItem("a#1", project: "/work/beta", at: older), routedItem("b#1", project: "/work/gamma", at: newer),
                     routedItem("b#2", project: "/work/gamma", at: older)]
        let projects = try projectEntries(items: items)
        XCTAssertEqual(projects.map { $0["name"] as? String }, ["gamma", "beta", "Alpha", "zeta"],
                       "newest first, then the ones never used by name")
        XCTAssertEqual(projects[0]["lastUsed"] as? String, ISO8601DateFormatter().string(from: newer))
        XCTAssertEqual(projects[1]["lastUsed"] as? String, ISO8601DateFormatter().string(from: older))
        XCTAssertNil(projects[2]["lastUsed"], "no item routed there: the key is left out")
        XCTAssertNil(projects[3]["lastUsed"])
    }

    func testProjectsListKeepsListeningProjectsFirstWhateverTheirLastUsed() throws {
        let items = [routedItem("a#1", project: "/work/gamma", at: Date(timeIntervalSince1970: 1_700_100_000)),
                     routedItem("b#1", project: "/work/zeta", at: Date(timeIntervalSince1970: 1_600_000_000))]
        let projects = try projectEntries(items: items, sessions: [live("/work/zeta")])
        XCTAssertEqual(projects.map { $0["name"] as? String }, ["zeta", "gamma", "Alpha", "beta"])
        XCTAssertEqual(projects[0]["live"] as? Bool, true)
        XCTAssertNotNil(projects[0]["lastUsed"], "a listening project also shows when it was last used")
    }
}
