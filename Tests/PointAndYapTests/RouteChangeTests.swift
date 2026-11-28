import XCTest
@testable import PointAndYap

/// K2: the "Change" button on "Sent to X": the route.change bridge method, the picker answer that writes the route, and the choices.
@MainActor
final class RouteChangeTests: XCTestCase {
    private let backend = Project(name: "backend", path: "/work/backend")
    private let web = Project(name: "web", path: "/work/web")

    private var suiteName = ""
    private var defaults: UserDefaults!
    private var realMakePanel: (([Project], @escaping @MainActor (Project?) -> Void) -> PickerHandle)?
    private var closedWindows = 0

    override class func setUp() { _ = PointAndYapTests.root }

    override func setUp() {
        suiteName = "RouteChangeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        closedWindows = 0
        realMakePanel = ProjectPicker.makePanel
        ProjectPicker.makePanel = { [unowned self] _, _ in PickerHandle(close: { self.closedWindows += 1 }) }
    }

    override func tearDown() {
        ProjectPicker.answer(nil)
        if let realMakePanel { ProjectPicker.makePanel = realMakePanel }
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func call(_ subject: WebBridge, _ params: [String: Any]) throws -> [String: Any] {
        try T1Support.replyObject(subject.handle(message: ["id": 1, "method": "route.change", "params": params]))
    }

    private func errorCode(_ reply: [String: Any]) -> String? {
        (reply["error"] as? [String: Any])?["code"] as? String
    }

    private func waitForPicker() async {
        var turns = 0
        while ProjectPicker.snapshot() == nil && turns < 200 {
            await Task.yield()
            turns += 1
        }
    }

    func testRouteChangeOpensThePickerForTheSession() throws {
        var asked: [String] = []
        let subject = WebBridge(defaults: defaults, loadItems: { [] }, changeRoute: { asked.append($0); return .opened })
        let reply = try call(subject, ["session": "2026-11-26_100000"])
        XCTAssertEqual((reply["result"] as? [String: Any])?["opened"] as? Bool, true)
        XCTAssertEqual(asked, ["2026-11-26_100000"])
    }

    func testRouteChangeNeedsASafeSessionId() throws {
        var asked: [String] = []
        let subject = WebBridge(defaults: defaults, loadItems: { [] }, changeRoute: { asked.append($0); return .opened })
        for bad in [NSNull(), "", "a/b", "..", "x..y", 5, true] as [Any] {
            XCTAssertEqual(errorCode(try call(subject, ["session": bad])), "bad_params", "\(bad)")
        }
        XCTAssertEqual(errorCode(try call(subject, [:])), "bad_params")
        XCTAssertTrue(asked.isEmpty)
    }

    func testRouteChangeIsNotAvailableWithoutTheApp() throws {
        let subject = WebBridge(defaults: defaults, loadItems: { [] })
        XCTAssertEqual(errorCode(try call(subject, ["session": "s1"])), "not_available")
    }

    func testRouteChangeMapsMissingAndBusy() throws {
        for (result, code) in [(WebBridge.ChangeRouteResult.missing, "not_found"), (.busy, "busy")] {
            let subject = WebBridge(defaults: defaults, loadItems: { [] }, changeRoute: { _ in result })
            XCTAssertEqual(errorCode(try call(subject, ["session": "s1"])), code)
        }
    }

    func testAPickWritesAPickedRouteAndClosesThePicker() async throws {
        let dir = try T1Support.makeSession("2026-11-26_route-change-pick", project: "/work/backend")
        defer { try? FileManager.default.removeItem(at: dir) }
        let state = AppState()
        let task = Task { @MainActor in await state.routeByPicking(dir, among: [backend, web], suggested: "/work/backend") }
        await waitForPicker()
        let snapshot = try XCTUnwrap(ProjectPicker.snapshot())
        XCTAssertEqual(snapshot.session, dir.lastPathComponent)
        XCTAssertEqual(snapshot.choices.map(\.suggested), [true, false])
        XCTAssertTrue(ProjectPicker.answer(web))
        let picked = await task.value
        XCTAssertEqual(picked, web)
        XCTAssertEqual(Router.readRoute(dir), RouteInfo(project: "web", path: "/work/web", how: "picked"))
        XCTAssertEqual(closedWindows, 1)
    }

    func testSkippingThePickerKeepsTheRoute() async throws {
        let dir = try T1Support.makeSession("2026-11-26_route-change-skip", project: "/work/backend")
        defer { try? FileManager.default.removeItem(at: dir) }
        let state = AppState()
        let task = Task { @MainActor in await state.routeByPicking(dir, among: [backend, web], suggested: "/work/backend") }
        await waitForPicker()
        XCTAssertTrue(ProjectPicker.answer(nil))
        let picked = await task.value
        XCTAssertNil(picked)
        XCTAssertEqual(Router.readRoute(dir)?.path, "/work/backend")
        XCTAssertEqual(Router.readRoute(dir)?.how, "said")
    }

    func testChangeForAnUnknownRecordingIsMissing() {
        XCTAssertEqual(AppState().changeProject(session: "2026-11-26_no-such-recording"), .missing)
    }

    func testChangeIsBusyWhileAnotherPickerIsOpen() async throws {
        let dir = try T1Support.makeSession("2026-11-26_route-change-busy", project: "/work/backend")
        defer { try? FileManager.default.removeItem(at: dir) }
        let other = Task { @MainActor in await ProjectPicker.ask([backend, web], session: "other") }
        await waitForPicker()
        XCTAssertEqual(AppState().changeProject(session: dir.lastPathComponent), .busy)
        ProjectPicker.answer(nil)
        _ = await other.value
    }

    func testChangeOpensThePickerWithTheListeningProjectFirstAndTheCurrentOneSuggested() async throws {
        let dir = try T1Support.makeSession("2026-11-28_route-change-opened", project: "/work/backend")
        defer { try? FileManager.default.removeItem(at: dir) }
        let live = [LiveSession(pid: 1, cwd: "/work/web", agent: "Claude Code", started: Date(), lastSeen: Date())]
        let state = AppState()
        let result = state.changeProject(session: dir.lastPathComponent, known: { [backend, web] }, listening: { live })
        XCTAssertEqual(result, .opened)
        await waitForPicker()
        let snapshot = try XCTUnwrap(ProjectPicker.snapshot())
        XCTAssertEqual(snapshot.session, dir.lastPathComponent)
        XCTAssertEqual(snapshot.choices.map(\.name), ["web", "backend"])
        XCTAssertEqual(snapshot.choices.map(\.suggested), [false, true])
        ProjectPicker.answer(nil)
    }

    func testChangeIsMissingWhenNoProjectIsKnown() throws {
        let dir = try T1Support.makeSession("2026-11-28_route-change-no-projects", project: "/work/backend")
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = AppState().changeProject(session: dir.lastPathComponent, known: { [] }, listening: { [] })
        XCTAssertEqual(result, .missing)
        XCTAssertNil(ProjectPicker.snapshot())
    }

    func testTheChoicesPutProjectsWithARunningSessionFirst() {
        let docs = Project(name: "docs", path: "/work/docs")
        let live = [LiveSession(pid: 1, cwd: "/work/docs", agent: "Claude Code", started: Date(), lastSeen: Date())]
        let choices = AppState.changeChoices(known: [backend, web, docs], live: live)
        XCTAssertEqual(choices.map(\.name), ["docs", "backend", "web"])
        XCTAssertEqual(AppState.changeChoices(known: [backend, web], live: []).map(\.name), ["backend", "web"])
    }
}
