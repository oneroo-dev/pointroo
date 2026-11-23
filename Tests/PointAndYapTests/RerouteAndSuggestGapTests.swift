import XCTest
@testable import PointAndYap

/// T1: reroute and unroute on real (temporary) recordings through the bridge, a picked route that survives routing, and the
/// edges of Router.suggest.
final class RerouteAndSuggestGapTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override class func setUp() { _ = PointAndYapTests.root }

    override func setUp() {
        suiteName = "RerouteAndSuggestGapTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private let oldProject = Project(name: "t1-old", path: "/work/t1-old")
    private let newProject = Project(name: "t1-new", path: "/work/t1-new")

    private func makeSession(_ id: String, project: String?) throws -> URL {
        let directory = try T1Support.makeSession(id, project: project)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func bridge() -> WebBridge {
        let known = [oldProject, newProject]
        return WebBridge(defaults: defaults, loadItems: { Items.all() },
                         findProject: { text in known.first { $0.name == text } })
    }

    private func call(_ method: String, id: String, project: String? = nil) throws -> [String: Any] {
        var params: [String: Any] = ["id": id]
        if let project { params["project"] = project }
        return try T1Support.replyObject(bridge().handle(message: ["id": 1, "method": method, "params": params]))
    }

    private func code(_ reply: [String: Any]) -> String? {
        (reply["error"] as? [String: Any])?["code"] as? String
    }

    private func firstItem(_ directory: URL) throws -> Item {
        try XCTUnwrap(Items.items(in: directory, state: Items.readState(directory)).items.first)
    }

    func testRerouteMovesAnOpenItemAndPicksTheProject() throws {
        let directory = try makeSession("2031-07-01_100000", project: oldProject.path)
        let reply = try call("items.reroute", id: "2031-07-01_100000#1", project: "t1-new")
        XCTAssertEqual((reply["result"] as? [String: Any])?["moved"] as? Bool, true)
        let route = try XCTUnwrap(Router.readRoute(directory))
        XCTAssertEqual(route, RouteInfo(project: "t1-new", path: "/work/t1-new", how: "picked"))
        XCTAssertEqual(try firstItem(directory).project, "/work/t1-new")
        XCTAssertEqual(try firstItem(directory).routeHow, "picked")
    }

    func testRerouteGivesAnInProgressItemBackToOpenWithANote() throws {
        let directory = try makeSession("2031-07-02_100000", project: oldProject.path)
        XCTAssertEqual(Items.set(["2031-07-02_100000#1"], status: "in_progress", agent: "a", note: nil).changed, ["2031-07-02_100000#1"])
        XCTAssertEqual(try firstItem(directory).status, "in_progress")
        let reply = try call("items.reroute", id: "2031-07-02_100000#1", project: "t1-new")
        XCTAssertEqual((reply["result"] as? [String: Any])?["moved"] as? Bool, true)
        let item = try firstItem(directory)
        XCTAssertEqual(item.status, "open")
        XCTAssertEqual(item.note, "Moved to t1-new")
        XCTAssertEqual(item.project, "/work/t1-new")
    }

    func testRerouteRefusesADoneItemAndKeepsItsRoute() throws {
        let directory = try makeSession("2031-07-03_100000", project: oldProject.path)
        _ = Items.set(["2031-07-03_100000#1"], status: "done", agent: "a", note: "fixed")
        let reply = try call("items.reroute", id: "2031-07-03_100000#1", project: "t1-new")
        XCTAssertEqual(code(reply), "refused")
        XCTAssertEqual(Router.readRoute(directory)?.path, "/work/t1-old")
        XCTAssertEqual(Router.readRoute(directory)?.how, "said")
    }

    func testRerouteOfAMissingItemOrAnUnsafeIdIsNotFoundAndWritesNothing() throws {
        let directory = try makeSession("2031-07-04_100000", project: oldProject.path)
        for id in ["2031-07-04_999999#1", "2031-07-04_100000#9", "../2031-07-04_100000#1", "2031-07-04_100000/x#1", "a#b"] {
            XCTAssertEqual(code(try call("items.reroute", id: id, project: "t1-new")), "not_found", id)
        }
        XCTAssertEqual(Router.readRoute(directory)?.path, "/work/t1-old")
    }

    func testRerouteToAnUnknownProjectLeavesTheRouteAndTheItemAlone() throws {
        let directory = try makeSession("2031-07-05_100000", project: oldProject.path)
        let reply = try call("items.reroute", id: "2031-07-05_100000#1", project: "t1-nowhere")
        XCTAssertEqual(code(reply), "not_found")
        XCTAssertEqual(Router.readRoute(directory)?.how, "said")
        XCTAssertEqual(try firstItem(directory).status, "open")
    }

    func testARerouteRemovesTheSuggestionAndTheItemStopsShowingIt() throws {
        let directory = try makeSession("2031-07-06_100000", project: nil)
        Router.writeSuggest(SuggestInfo(path: "/work/t1-old", how: "related"), to: directory)
        XCTAssertEqual(try firstItem(directory).suggested, "/work/t1-old")
        XCTAssertEqual(code(try call("items.reroute", id: "2031-07-06_100000#1", project: "t1-new")), nil)
        XCTAssertNil(Router.readSuggest(directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: Router.suggestURL(directory).path))
        let item = try firstItem(directory)
        XCTAssertNil(item.suggested)
        XCTAssertEqual(item.project, "/work/t1-new")
    }

    private func events() -> SessionEvents {
        SessionEvents(started: Date(), duration: 3, samples: [], points: [], frames: [])
    }

    private func live(_ cwd: String, pid: Int32 = 1) -> LiveSession {
        LiveSession(pid: pid, cwd: cwd, agent: "claude", started: Date(), lastSeen: Date())
    }

    func testAPickedRouteSurvivesRoutingTheSameRecordingAgain() throws {
        let directory = try makeSession("2031-07-07_100000", project: nil)
        XCTAssertEqual(code(try call("items.reroute", id: "2031-07-07_100000#1", project: "t1-new")), nil)
        let saidOther = [Word(text: "t1-old", start: 0, end: 1)]
        Router.routeSession(directory, events: events(), words: saidOther, live: [live("/work/solo")],
                            knownProjects: [oldProject, newProject], items: [], autoSendSingle: true, now: Date())
        XCTAssertEqual(Router.readRoute(directory), RouteInfo(project: "t1-new", path: "/work/t1-new", how: "picked"))
        XCTAssertNil(Router.readSuggest(directory), "no suggestion is written for a picked recording")
        XCTAssertEqual(try firstItem(directory).project, "/work/t1-new")
    }

    func testAPickedRouteSurvivesRoutingWhenNothingElseFits() throws {
        let directory = try makeSession("2031-07-08_100000", project: nil)
        Router.writeRoute(RouteInfo(project: "t1-new", path: "/work/t1-new", how: "picked"), to: directory)
        Router.routeSession(directory, events: events(), words: [Word(text: "hello", start: 0, end: 1)], live: [],
                            knownProjects: [oldProject, newProject], items: [], autoSendSingle: false, now: Date())
        XCTAssertEqual(Router.readRoute(directory)?.how, "picked")
        XCTAssertEqual(Router.readRoute(directory)?.path, "/work/t1-new")
    }

    func testARouteThatWasNotPickedIsReplacedByTheNextRouting() throws {
        let directory = try makeSession("2031-07-09_100000", project: oldProject.path)
        Router.routeSession(directory, events: events(), words: [Word(text: "t1-new", start: 0, end: 1)], live: [],
                            knownProjects: [oldProject, newProject], items: [], autoSendSingle: true, now: Date())
        XCTAssertEqual(Router.readRoute(directory)?.path, "/work/t1-new")
        XCTAssertEqual(Router.readRoute(directory)?.how, "said")
    }

    func testUnrouteOfAnOpenItemRemovesTheRouteAndKeepsTheProjectAsASuggestion() throws {
        let directory = try makeSession("2031-07-10_100000", project: oldProject.path)
        let reply = try call("items.unroute", id: "2031-07-10_100000#1")
        XCTAssertEqual((reply["result"] as? [String: Any])?["unrouted"] as? Bool, true)
        XCTAssertNil(Router.readRoute(directory))
        XCTAssertEqual(Router.readSuggest(directory), SuggestInfo(path: "/work/t1-old", how: "undone"))
        XCTAssertNil(try firstItem(directory).project)
        let again = try call("items.unroute", id: "2031-07-10_100000#1")
        XCTAssertEqual((again["result"] as? [String: Any])?["unrouted"] as? Bool, true, "a recording with no route answers unrouted too")
        XCTAssertEqual(Router.readSuggest(directory)?.how, "undone")
    }

    func testUnrouteRefusesAnItemAnAgentTookAndKeepsTheRoute() throws {
        let directory = try makeSession("2031-07-11_100000", project: oldProject.path)
        _ = Items.set(["2031-07-11_100000#1"], status: "in_progress", agent: "a", note: nil)
        XCTAssertEqual(code(try call("items.unroute", id: "2031-07-11_100000#1")), "refused")
        XCTAssertEqual(Router.readRoute(directory)?.path, "/work/t1-old")
        XCTAssertNil(Router.readSuggest(directory))
    }

    func testUnrouteRefusesADoneItemAndKeepsTheRoute() throws {
        let directory = try makeSession("2031-07-12_100000", project: oldProject.path)
        _ = Items.set(["2031-07-12_100000#1"], status: "done", agent: "a", note: "ok")
        XCTAssertEqual(code(try call("items.unroute", id: "2031-07-12_100000#1")), "refused")
        XCTAssertEqual(Router.readRoute(directory)?.how, "said")
    }

    func testUnrouteOfAMissingItemOrAnUnsafeIdIsNotFound() throws {
        _ = try makeSession("2031-07-13_100000", project: oldProject.path)
        for id in ["2031-07-13_999999#1", "2031-07-13_100000#7", "../x#1", "a/b#1", "x..y#1", "#1"] {
            XCTAssertEqual(code(try call("items.unroute", id: id)), "not_found", id)
        }
    }

    func testUnrouteOfATrashedItemWorksLikeAnOpenOne() throws {
        let directory = try makeSession("2031-07-14_100000", project: oldProject.path)
        _ = Items.set(["2031-07-14_100000#1"], status: "trashed", agent: "user", note: nil)
        XCTAssertEqual(try call("items.unroute", id: "2031-07-14_100000#1")["result"] as? [String: Bool], ["unrouted": true])
        XCTAssertNil(Router.readRoute(directory))
    }

    private let known = [Project(name: "pointroo", path: "/work/pointroo"), Project(name: "shop", path: "/work/shop-app")]

    func testSuggestLastSentIsInsideAtExactlyThirtyMinutesAndOutsideOneSecondLater() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func guess(secondsAgo: Double) -> Router.Result? {
            Router.suggest(words: [], points: [], projects: known,
                           lastSent: (path: "/work/shop-app", at: now.addingTimeInterval(-secondsAgo)), now: now)
        }
        XCTAssertEqual(Router.lastSentWindow, 1800)
        XCTAssertEqual(guess(secondsAgo: 1800), Router.Result(path: "/work/shop-app", how: "lastsent"))
        XCTAssertEqual(guess(secondsAgo: 1799.999)?.how, "lastsent")
        XCTAssertNil(guess(secondsAgo: 1800.001))
        XCTAssertNil(guess(secondsAgo: 1801))
        XCTAssertEqual(guess(secondsAgo: 0)?.how, "lastsent", "sent this very moment")
    }

    func testSuggestIgnoresALastSentThatIsInTheFuture() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for ahead in [0.001, 1, 60, 3600] as [Double] {
            let guess = Router.suggest(words: [], points: [], projects: known, lastSent: (path: "/work/shop-app", at: now.addingTimeInterval(ahead)), now: now)
            XCTAssertNil(guess, "\(ahead) s ahead")
        }
    }

    func testAFutureLastSentFallsThroughToTheOnlyListeningProject() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let guess = Router.suggest(words: [], points: [], projects: known, live: [live("/work/solo")],
                                   lastSent: (path: "/work/shop-app", at: now.addingTimeInterval(120)), now: now)
        XCTAssertEqual(guess, Router.Result(path: "/work/solo", how: "only"))
    }

    func testTwoSessionsInTheSameFolderCountAsOneListeningProject() {
        let two = Router.suggest(words: [], points: [], projects: known, live: [live("/work/solo", pid: 1), live("/work/solo", pid: 2)])
        XCTAssertEqual(two, Router.Result(path: "/work/solo", how: "only"))
        let spelled = Router.suggest(words: [], points: [], projects: known, live: [live("/work/solo", pid: 1), live("/work/solo/", pid: 2)])
        XCTAssertEqual(spelled?.how, "only", "a trailing slash is the same folder")
        let three = Router.suggest(words: [], points: [], projects: known,
                                   live: [live("/work/solo", pid: 1), live("/work/solo", pid: 2), live("/work/solo", pid: 3)])
        XCTAssertEqual(three?.path, "/work/solo")
    }

    func testTwoSessionsInDifferentFoldersGiveNoOnlyGuessEvenWhenOneIsInsideTheOther() {
        XCTAssertNil(Router.suggest(words: [], points: [], projects: known, live: [live("/work/solo", pid: 1), live("/work/solo/app", pid: 2)]))
        XCTAssertNil(Router.suggest(words: [], points: [], projects: known, live: [live("/work/a", pid: 1), live("/work/b", pid: 2), live("/work/a", pid: 3)]))
    }

    func testTwoSessionsInTheSameFolderStillAutoSendOnTheRoutePath() {
        let result = Router.route(words: [], points: [], projects: known, live: [live("/work/solo", pid: 1), live("/work/solo", pid: 2)])
        XCTAssertEqual(result, Router.Result(path: "/work/solo", how: "only"))
        XCTAssertNil(Router.route(words: [], points: [], projects: known, live: [live("/work/solo", pid: 1), live("/work/other", pid: 2)]))
    }

    func testLastSentIgnoresItemsWithAProjectButNoRouteOrAnUnreadableSessionName() {
        func made(_ session: String, project: String?, how: String?) -> Item {
            var item = Item(id: "\(session)#1", session: session, n: 1, title: "t", body: "", crops: [], status: "open", at: nil)
            item.project = project
            item.routeHow = how
            return item
        }
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [made("a", project: "/work/a", how: "said"), made("b", project: "/work/b", how: nil), made("c", project: nil, how: "said")]
        XCTAssertEqual(Router.lastSent(items, recordedAt: { $0 == "a" ? at : nil })?.path, "/work/a")
        XCTAssertNil(Router.lastSent(items, recordedAt: { $0 == "b" || $0 == "c" ? at : nil }))
        XCTAssertNil(Router.lastSent([]))
    }

    func testLastSentFeedsSuggestAtTheThirtyMinuteEdge() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var sent = Item(id: "a#1", session: "a", n: 1, title: "t", body: "", crops: [], status: "open", at: nil)
        sent.project = "/work/shop-app"
        sent.routeHow = "said"
        func guess(secondsAgo: Double) -> Router.Result? {
            let found = Router.lastSent([sent], recordedAt: { _ in now.addingTimeInterval(-secondsAgo) })
            return Router.suggest(words: [], points: [], projects: known, lastSent: found, now: now)
        }
        XCTAssertEqual(guess(secondsAgo: 1800)?.how, "lastsent")
        XCTAssertNil(guess(secondsAgo: 1801))
    }

    func testATieOnTheScreenFallsThroughToTheLastSentProject() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func point(_ window: String) -> PointEvent {
            PointEvent(index: 0, t: 0, end: 1, at: Pt(x: 0, y: 0), kind: "dwell", app: "Safari", bundleID: nil,
                       window: window, url: nil, element: nil, frame: nil)
        }
        let guess = Router.suggest(words: [], points: [point("pointrooapp"), point("shop-app")], projects: known,
                                   lastSent: (path: "/work/other", at: now.addingTimeInterval(-60)), now: now)
        XCTAssertEqual(guess, Router.Result(path: "/work/other", how: "lastsent"))
    }
}
