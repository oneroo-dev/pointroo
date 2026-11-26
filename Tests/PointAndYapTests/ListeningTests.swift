import XCTest
@testable import PointAndYap

/// R40: a session listens only when it called wait_for_next lately. A session that runs but does not wait is just open.
@MainActor
final class ListeningTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ folder: String, pid: Int32, waitedSecondsAgo: TimeInterval?) -> LiveSession {
        LiveSession(pid: pid, cwd: folder, agent: "Claude Code", started: now.addingTimeInterval(-3600),
                    lastSeen: now, lastWaited: waitedSecondsAgo.map { now.addingTimeInterval(-$0) })
    }

    func testListeningKeepsFourMinutesAndDropsSixMinutesAndNever() {
        let fresh = session("/work/fresh", pid: 1, waitedSecondsAgo: 4 * 60)
        let stale = session("/work/stale", pid: 2, waitedSecondsAgo: 6 * 60)
        let never = session("/work/never", pid: 3, waitedSecondsAgo: nil)
        let result = LiveSessions.listening(from: [fresh, stale, never], now: now)
        XCTAssertEqual(result.map(\.cwd), ["/work/fresh"])
    }

    func testOldLiveFileWithoutLastWaitedDecodesAndDoesNotListen() throws {
        let json = """
        {"pid": 42, "cwd": "/work/old", "agent": "Claude Code", "started": "2026-11-20T10:00:00Z", "lastSeen": "2026-11-20T10:05:00Z"}
        """
        let decoded = try JSONDecoder.iso.decode(LiveSession.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.pid, 42)
        XCTAssertNil(decoded.lastWaited)
        XCTAssertTrue(LiveSessions.listening(from: [decoded], now: now).isEmpty)
    }

    func testLastWaitedSurvivesEncodeAndDecode() throws {
        let original = session("/work/a", pid: 7, waitedSecondsAgo: 30)
        let data = try JSONEncoder.pretty.encode(original)
        let decoded = try JSONDecoder.iso.decode(LiveSession.self, from: data)
        XCTAssertEqual(decoded.lastWaited, original.lastWaited)
    }

    func testRouterOnlyIgnoresAnOpenSessionThatDoesNotListen() {
        let open = session("/work/busy", pid: 1, waitedSecondsAgo: nil)
        let listening = session("/work/waiting", pid: 2, waitedSecondsAgo: 10)
        let projects = [Project(name: "busy", path: "/work/busy"), Project(name: "waiting", path: "/work/waiting")]
        let result = Router.route(words: [], points: [], projects: projects, live: [open, listening], listening: [listening])
        XCTAssertEqual(result, Router.Result(path: "/work/waiting", how: "only"))
    }

    func testRouterOnlyGivesNothingWhenNobodyListens() {
        let open = session("/work/busy", pid: 1, waitedSecondsAgo: nil)
        let projects = [Project(name: "busy", path: "/work/busy")]
        XCTAssertNil(Router.route(words: [], points: [], projects: projects, live: [open], listening: []))
    }

    func testSuggestOnlyIgnoresAnOpenSessionThatDoesNotListen() {
        let open = session("/work/busy", pid: 1, waitedSecondsAgo: nil)
        let projects = [Project(name: "busy", path: "/work/busy")]
        XCTAssertNil(Router.suggest(words: [], points: [], projects: projects, live: [open], listening: [], now: now))
    }

    func testPickerShowsWhenOneSessionIsOpenAndNoneListens() {
        let busy = Project(name: "busy", path: "/work/busy")
        let other = Project(name: "other", path: "/work/other")
        let choices = AppState.pickerChoices(known: [busy, other], live: [])
        XCTAssertEqual(choices.map(\.name), ["busy", "other"])
    }

    func testPickerStaysHiddenWhenExactlyOneFolderListens() {
        let busy = Project(name: "busy", path: "/work/busy")
        let other = Project(name: "other", path: "/work/other")
        let listening = session("/work/other", pid: 2, waitedSecondsAgo: 5)
        XCTAssertTrue(AppState.pickerChoices(known: [busy, other], live: [listening]).isEmpty)
    }
}
