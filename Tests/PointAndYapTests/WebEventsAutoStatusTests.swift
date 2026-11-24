import XCTest
@testable import PointAndYap

/// T8: status.changed goes out once when the auto-start parts of the status change, and never when nothing changed.
/// This tests WebEvents.status directly with plain AppStatus values: no timer, no disk.
final class WebEventsAutoStatusTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_000)
    private let endedAt = Date(timeIntervalSince1970: 2_000)

    private func baseStatus() -> AppStatus {
        AppStatus.make(boundPort: 6742, configuredPort: 6742, text: "running", live: [],
                       microphone: true, screenRecording: true, accessibility: true)
    }

    private func run(_ project: String) -> AutoStart.Run {
        AutoStart.Run(project: project, startedAt: startedAt)
    }

    private func lastRun() -> AutoStart.LastRun {
        AutoStart.LastRun(project: "/work/shop", endedAt: endedAt, exitCode: 0, cost: 0.25)
    }

    func testFirstCallIsTheBaselineAndSendsOneEvent() {
        var events = WebEvents()
        XCTAssertEqual(events.status(baseStatus()).map(\.name), ["status.changed"])
    }

    func testSameStatusSendsNothing() {
        var events = WebEvents()
        _ = events.status(baseStatus())
        XCTAssertTrue(events.status(baseStatus()).isEmpty)
        XCTAssertTrue(events.status(baseStatus()).isEmpty)
    }

    func testAddingAnAutoRunSendsOneEventWithItInTheData() {
        var events = WebEvents()
        _ = events.status(baseStatus())
        var changed = baseStatus()
        changed.autoRuns = [run("/work/shop")]
        let result = events.status(changed)
        XCTAssertEqual(result.map(\.name), ["status.changed"])
        let runs = result[0].data["autoRuns"] as? [[String: Any]]
        XCTAssertEqual(runs?.count, 1)
        XCTAssertEqual(runs?.first?["project"] as? String, "/work/shop")
        XCTAssertNil(result[0].data["lastAutoRun"])
    }

    func testRepeatingTheAutoRunStatusSendsNothing() {
        var events = WebEvents()
        _ = events.status(baseStatus())
        var changed = baseStatus()
        changed.autoRuns = [run("/work/shop")]
        XCTAssertEqual(events.status(changed).count, 1)
        XCTAssertTrue(events.status(changed).isEmpty)
    }

    func testSettingTheLastAutoRunSendsOneEventWithItInTheData() {
        var events = WebEvents()
        var before = baseStatus()
        before.autoRuns = [run("/work/shop")]
        _ = events.status(before)
        var after = before
        after.lastAutoRun = lastRun()
        let result = events.status(after)
        XCTAssertEqual(result.map(\.name), ["status.changed"])
        let last = result[0].data["lastAutoRun"] as? [String: Any]
        XCTAssertEqual(last?["project"] as? String, "/work/shop")
        XCTAssertEqual(last?["exitCode"] as? Int, 0)
        XCTAssertEqual(last?["cost"] as? Double, 0.25)
        XCTAssertTrue(events.status(after).isEmpty)
    }

    func testAutoRunEndingSendsOneEventWhenRunLeavesAndLastRunAppearsTogether() {
        var events = WebEvents()
        var running = baseStatus()
        running.autoRuns = [run("/work/shop")]
        _ = events.status(running)
        var ended = baseStatus()
        ended.lastAutoRun = lastRun()
        let result = events.status(ended)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual((result[0].data["autoRuns"] as? [[String: Any]])?.count, 0)
        XCTAssertNotNil(result[0].data["lastAutoRun"])
    }

    func testEventDataMatchesTheStatusDictionary() {
        var events = WebEvents()
        var status = baseStatus()
        status.autoRuns = [run("/work/shop"), run("/work/blog")]
        status.lastAutoRun = lastRun()
        let result = events.status(status)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(NSDictionary(dictionary: result[0].data), NSDictionary(dictionary: status.dictionary))
    }
}
