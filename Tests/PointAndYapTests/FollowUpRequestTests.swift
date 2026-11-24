import XCTest
@testable import PointAndYap

/// R30: "Say more" on a done notice. recording.start takes followUp, saves a request, and the next recording is routed
/// to that item's project as its follow-up.
final class FollowUpRequestTests: XCTestCase {
    private var folder: URL!
    private var suiteName = ""
    private var defaults: UserDefaults!

    override class func setUp() { _ = PointAndYapTests.root }

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("follow-\(UUID().uuidString)")
        suiteName = "FollowUpRequestTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private let started = Date(timeIntervalSince1970: 1_800_000_000)
    private let known = [Project(name: "pointroo", path: "/work/pointroo"), Project(name: "shop", path: "/work/shop-app")]
    private let words = [Word(text: "fix", start: 0, end: 1), Word(text: "this", start: 1, end: 2)]

    private final class Fake {
        var phase = "idle"
        var actions: [WebBridge.RecordingAction] = []
    }

    private func item(_ id: String, status: String = "done", project: String? = "/work/shop-app") -> Item {
        var made = Item(id: id, session: "s", n: 1, title: "Fix it", body: "body", crops: [], status: status,
                        at: Date(timeIntervalSince1970: 100))
        made.by = "claude"
        made.project = project
        return made
    }

    private func bridge(_ fake: Fake, items: [Item]) -> WebBridge {
        WebBridge(defaults: defaults, loadItems: { items }, loadProjects: { [] }, loadLive: { [] },
                  controlRecording: { fake.actions.append($0) },
                  loadRecording: { RecordingSnapshot(phase: fake.phase, startedAt: nil, points: 0) },
                  now: { Date(timeIntervalSince1970: 1_800_000_000) },
                  followUpStore: FollowUpStore(folder: folder))
    }

    private func code(_ subject: WebBridge, _ method: String, _ params: [String: Any] = [:]) throws -> String? {
        try T1Support.errorCode(subject.handle(message: ["id": 1, "method": method, "params": params]))
    }

    private func result(_ subject: WebBridge, _ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        let reply = try T1Support.replyObject(subject.handle(message: ["id": 1, "method": method, "params": params]))
        return try XCTUnwrap(reply["result"] as? [String: Any], "\(reply)")
    }

    private var store: FollowUpStore { FollowUpStore(folder: folder) }

    private func makeSession(_ id: String) throws -> URL {
        let source = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/2026-10-17_120000", withExtension: nil))
        let target = PointAndYapTests.root.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)
        try? FileManager.default.removeItem(at: Router.routeURL(target))
        try? FileManager.default.removeItem(at: Router.suggestURL(target))
        addTeardownBlock { try? FileManager.default.removeItem(at: target) }
        return target
    }

    private func events(points: [PointEvent] = []) -> SessionEvents {
        SessionEvents(started: started, duration: 3, samples: [], points: points, frames: [])
    }

    private func point(window: String) -> PointEvent {
        PointEvent(index: 0, t: 0, end: 1, at: Pt(x: 0, y: 0), kind: "dwell", app: "Safari", bundleID: nil,
                   window: window, url: nil, element: nil, frame: nil)
    }

    private func saveRequest(secondsBefore: TimeInterval) {
        store.save(FollowUpRequest(id: "s#9", path: "/work/shop-app", at: started.addingTimeInterval(-secondsBefore)))
    }

    private func route(_ directory: URL, words: [Word]? = nil, points: [PointEvent] = []) {
        Router.routeSession(directory, events: events(points: points), words: words ?? self.words, live: [],
                            knownProjects: known, items: [], autoSendSingle: true, now: started, followUpFolder: folder)
    }

    func testUnknownOpenAndUnroutedItemsAreBadParams() throws {
        let fake = Fake()
        let subject = bridge(fake, items: [item("a#1", status: "open"), item("b#1", project: nil), item("c#1")])
        XCTAssertEqual(try code(subject, "recording.start", ["followUp": "nope#1"]), "bad_params")
        XCTAssertEqual(try code(subject, "recording.start", ["followUp": "a#1"]), "bad_params")
        XCTAssertEqual(try code(subject, "recording.start", ["followUp": "b#1"]), "bad_params")
        XCTAssertEqual(try code(subject, "recording.start", ["followUp": 5]), "bad_params")
        XCTAssertTrue(fake.actions.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.file.path))
    }

    func testBusyBeatsFollowUp() throws {
        let fake = Fake()
        fake.phase = "recording"
        let subject = bridge(fake, items: [item("c#1")])
        XCTAssertEqual(try code(subject, "recording.start", ["followUp": "c#1"]), "busy")
        XCTAssertEqual(try code(subject, "recording.start", ["followUp": "nope#1"]), "busy")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.file.path))
    }

    func testStartResultCarriesFollowUpAndSavesTheRequest() throws {
        let fake = Fake()
        let reply = try result(bridge(fake, items: [item("c#1")]), "recording.start", ["followUp": "c#1"])
        XCTAssertEqual(reply["started"] as? Bool, true)
        XCTAssertEqual(reply["followUp"] as? String, "c#1")
        XCTAssertEqual(fake.actions.count, 1)
        let saved = try XCTUnwrap(store.take(recordingStarted: Date(timeIntervalSince1970: 1_800_000_001)))
        XCTAssertEqual(saved, FollowUpRequest(id: "c#1", path: "/work/shop-app", at: Date(timeIntervalSince1970: 1_800_000_000)))
    }

    func testStartWithoutFollowUpSavesNothing() throws {
        let fake = Fake()
        let reply = try result(bridge(fake, items: [item("c#1")]), "recording.start")
        XCTAssertEqual(reply["started"] as? Bool, true)
        XCTAssertNil(reply["followUp"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.file.path))
    }

    func testSavedRequestRoutesAsFollowUpWithNoLiveSessionAndAfter180Seconds() throws {
        saveRequest(secondsBefore: 500)
        let directory = try makeSession("r30-asked-a")
        route(directory)
        let info = try XCTUnwrap(Router.readRoute(directory))
        XCTAssertEqual(info.how, "followup")
        XCTAssertEqual(info.path, "/work/shop-app")
        XCTAssertEqual(info.follows, "s#9")
    }

    func testSaidNameStillWins() throws {
        saveRequest(secondsBefore: 30)
        let directory = try makeSession("r30-asked-b")
        route(directory, words: [Word(text: "pointroo", start: 0, end: 1)])
        let info = try XCTUnwrap(Router.readRoute(directory))
        XCTAssertEqual(info.how, "said")
        XCTAssertEqual(info.path, "/work/pointroo")
    }

    func testScreenLosesToTheAskedFollowUp() throws {
        saveRequest(secondsBefore: 30)
        let directory = try makeSession("r30-asked-c")
        route(directory, points: [point(window: "pointroo docs")])
        let info = try XCTUnwrap(Router.readRoute(directory))
        XCTAssertEqual(info.how, "followup")
        XCTAssertEqual(info.path, "/work/shop-app")
    }

    func testRouterRouteOrder() {
        let asked = (path: "/work/shop-app", id: "s#9")
        XCTAssertEqual(Router.route(words: [], points: [point(window: "pointroo docs")], projects: known, asked: asked),
                       Router.Result(path: "/work/shop-app", how: "followup", follows: "s#9"))
        XCTAssertEqual(Router.route(words: ["pointroo"], points: [], projects: known, asked: asked)?.how, "said")
    }

    func testRequestIsUsedOnce() throws {
        saveRequest(secondsBefore: 30)
        let first = try makeSession("r30-asked-d")
        route(first)
        XCTAssertEqual(Router.readRoute(first)?.how, "followup")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.file.path))
        let second = try makeSession("r30-asked-e")
        route(second)
        XCTAssertNil(Router.readRoute(second))
    }

    func testTooOldRequestIsIgnoredAndRemoved() throws {
        saveRequest(secondsBefore: 601)
        let directory = try makeSession("r30-asked-f")
        route(directory)
        XCTAssertNil(Router.readRoute(directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.file.path))
    }

    func testCancelRemovesTheRequest() throws {
        let fake = Fake()
        let subject = bridge(fake, items: [item("c#1")])
        _ = try result(subject, "recording.start", ["followUp": "c#1"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.file.path))
        fake.phase = "recording"
        XCTAssertEqual(try result(subject, "recording.cancel")["cancelled"] as? Bool, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.file.path))
    }
}
