import XCTest
@testable import PointAndYap

/// R5, the backend the new screens need: port pick, re-route, practice recordings, deep links and the live point count.
final class BackendTests: XCTestCase {
    override class func setUp() { _ = PointAndYapTests.root }

    private func makeSession(_ id: String, project: String? = "/work/backend-a") throws -> URL {
        let source = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/2026-10-17_120000", withExtension: nil))
        let target = PointAndYapTests.root.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)
        let events = try JSONDecoder.iso.decode(SessionEvents.self, from: Data(contentsOf: target.appendingPathComponent("events.json")))
        let words = try JSONDecoder().decode([Word].self, from: Data(contentsOf: target.appendingPathComponent("transcript.json")))
        _ = Builder.build(dir: target, events: events, words: words)
        if let project {
            Router.writeRoute(RouteInfo(project: URL(fileURLWithPath: project).lastPathComponent, path: project, how: "said"), to: target)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: target) }
        return target
    }

    func testPicksTheNextFreePortAfterTheCurrentOne() {
        XCTAssertEqual(MCPPort.nextFree(after: 6742, isBusy: { $0 == 6742 }), 6743)
        XCTAssertEqual(MCPPort.nextFree(after: 6742, isBusy: { [6742, 6743, 6744].contains($0) }), 6745)
    }

    func testWrapsRoundInsideTheRange() {
        XCTAssertEqual(MCPPort.nextFree(after: 6759, isBusy: { $0 == 6759 }), 6740)
        XCTAssertEqual(MCPPort.nextFree(after: 6758, isBusy: { [6758, 6759, 6740].contains($0) }), 6741)
    }

    func testNeverLeavesTheFamilyRange() {
        XCTAssertNil(MCPPort.nextFree(after: 6742, isBusy: { _ in true }))
        for current in [1, 6739, 6742, 6760, 65535] {
            let port = MCPPort.nextFree(after: current, isBusy: { _ in false })
            XCTAssertTrue(port.map(MCPPort.range.contains) ?? false)
        }
    }

    func testNormalizesASavedPortOutsideTheRangeToTheDefault() {
        XCTAssertEqual(MCPPort.normalized(0), 6742)
        XCTAssertEqual(MCPPort.normalized(8080), 6742)
        XCTAssertEqual(MCPPort.normalized(6750), 6750)
    }

    func testUsesAnotherPortSavesItRestartsAndInstalls() {
        var saved: Int?
        var restarted: UInt16?
        var installed = false
        let result = MCPPort.useAnother(isBusy: { $0 == 6742 }, restart: { restarted = $0; return nil },
                                        install: { installed = true }, save: { saved = $0 }, current: 6742)
        XCTAssertEqual(result, .success(6743))
        XCTAssertEqual(saved, 6743)
        XCTAssertEqual(restarted, 6743)
        XCTAssertTrue(installed)
    }

    func testDoesNotInstallWhenTheRestartFailsOrNoPortIsFree() {
        var installed = false
        let failed = MCPPort.useAnother(isBusy: { _ in false }, restart: { _ in "could not start" },
                                        install: { installed = true }, save: { _ in }, current: 6742)
        XCTAssertEqual(failed, .failure(BackendError("could not start")))
        let none = MCPPort.useAnother(isBusy: { _ in true }, restart: { _ in nil },
                                      install: { installed = true }, save: { _ in }, current: 6742)
        if case .success = none { XCTFail("no port is free") }
        XCTAssertFalse(installed)
    }

    func testReroutesAnOpenItemAndLearnsTheRoute() throws {
        let directory = try makeSession("2026-11-23_100000")
        let project = Project(name: "other", path: "/work/backend-other")
        XCTAssertEqual(Items.reroute(id: "2026-11-23_100000#1", to: project), .moved)
        let route = try XCTUnwrap(Router.readRoute(directory))
        XCTAssertEqual(route.path, "/work/backend-other")
        XCTAssertEqual(route.how, "picked")
        XCTAssertTrue(Projects.load().contains { $0.path == "/work/backend-other" })
        let item = try XCTUnwrap(Items.items(in: directory, state: nil).items.first)
        XCTAssertEqual(item.project, "/work/backend-other")
    }

    func testRefusesToRerouteADoneItem() throws {
        let directory = try makeSession("2026-11-23_100100")
        _ = Items.set(["2026-11-23_100100#1"], status: "done", agent: "agent", note: "fixed")
        let result = Items.reroute(id: "2026-11-23_100100#1", to: Project(name: "other", path: "/work/backend-other"))
        XCTAssertEqual(result, .done)
        XCTAssertEqual(Router.readRoute(directory)?.path, "/work/backend-a")
    }

    func testRefusesToRerouteAnUnknownOrUnsafeId() {
        let project = Project(name: "other", path: "/work/backend-other")
        XCTAssertEqual(Items.reroute(id: "no-such-session#1", to: project), .missing)
        XCTAssertEqual(Items.reroute(id: "../x#1", to: project), .missing)
        XCTAssertEqual(Items.reroute(id: "a/b#1", to: project), .missing)
    }

    func testMarksPracticeItemsDoneByYouAndNeverHandsThemOut() throws {
        let directory = try makeSession("2026-11-23_100200", project: nil)
        Practice.mark(directory)
        let item = try XCTUnwrap(Items.items(in: directory, state: nil).items.first)
        XCTAssertTrue(item.practice)
        XCTAssertEqual(item.status, "done")
        XCTAssertEqual(item.by, "you")
        let handed = Items.openItems(limit: 10, take: true, agent: "agent")
        XCTAssertFalse(handed.contains { $0.session == "2026-11-23_100200" })
        let started = Items.set(["2026-11-23_100200#1"], status: "in_progress", agent: "agent", note: nil)
        XCTAssertTrue(started.changed.isEmpty)
        let listing = MCPServer.listItems("done")
        let text = ((listing["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined()
        XCTAssertTrue(text.contains("Practice"))
    }

    func testKeepsANormalItemOpenWithoutThePracticeFlag() throws {
        let directory = try makeSession("2026-11-23_100300")
        let item = try XCTUnwrap(Items.items(in: directory, state: nil).items.first)
        XCTAssertFalse(item.practice)
        XCTAssertEqual(item.status, "open")
    }

    func testAcceptsAValidItemLink() throws {
        let url = try XCTUnwrap(URL(string: "pointroo://item/2026-11-23_100000%231"))
        XCTAssertEqual(DeepLink.itemID(from: url), "2026-11-23_100000#1")
        let withFragment = try XCTUnwrap(URL(string: "pointroo://item/2026-11-23_100000#2"))
        XCTAssertEqual(DeepLink.itemID(from: withFragment), "2026-11-23_100000#2")
    }

    func testRejectsUnsafeOrWrongLinks() throws {
        for text in ["pointroo://item/..%2Fetc%231", "pointroo://item/a%2Fb%231", "pointroo://item/..", "pointroo://item/",
                     "pointroo://other/abc%231", "https://item/abc%231", "pointroo://item/abc%23x"] {
            let url = try XCTUnwrap(URL(string: text))
            XCTAssertNil(DeepLink.itemID(from: url), text)
        }
    }

    @MainActor
    func testOpensTheItemFromALinkAndPublishesThePointCount() throws {
        let state = AppState()
        XCTAssertEqual(state.pointCount, 0)
        XCTAssertFalse(state.handle(url: try XCTUnwrap(URL(string: "pointroo://item/..%231"))))
        XCTAssertNil(state.selectedItem)
        XCTAssertTrue(state.handle(url: try XCTUnwrap(URL(string: "pointroo://item/2026-11-23_100000%231"))))
        XCTAssertEqual(state.selectedItem, "2026-11-23_100000#1")
    }
}
