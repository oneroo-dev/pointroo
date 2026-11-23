import XCTest
@testable import PointAndYap

final class WebEventsTests: XCTestCase {
    private func item(_ id: String, status: String = "open", note: String? = nil, project: String? = nil) -> Item {
        var made = Item(id: id, session: "s", n: 1, title: "Fix it", body: "body", crops: [], status: status, at: nil)
        made.note = note
        made.project = project
        return made
    }

    private func question(_ id: String) -> Question {
        Question(id: id, project: "p", cwd: "/tmp", agent: "a", text: "Which?", choices: [], asked: Date(timeIntervalSince1970: 0))
    }

    func testFirstItemsCallEmitsWithTheRightCounts() {
        var events = WebEvents()
        let result = events.items([item("a#1"), item("b#1", status: "in_progress"), item("c#1", status: "done"), item("d#1")])
        XCTAssertEqual(result.map(\.name), ["items.changed"])
        XCTAssertEqual(result[0].data["count"] as? Int, 4)
        XCTAssertEqual(result[0].data["open"] as? Int, 2)
        XCTAssertEqual(result[0].data["inProgress"] as? Int, 1)
    }

    func testFirstItemsCallEmitsEvenWhenThereAreNone() {
        var events = WebEvents()
        XCTAssertEqual(events.items([]).count, 1)
        XCTAssertTrue(events.items([]).isEmpty)
    }

    func testSameItemsTwiceEmitsNothingTheSecondTime() {
        var events = WebEvents()
        _ = events.items([item("a#1")])
        XCTAssertTrue(events.items([item("a#1")]).isEmpty)
    }

    func testOrderOfItemsDoesNotMatter() {
        var events = WebEvents()
        _ = events.items([item("a#1"), item("b#1")])
        XCTAssertTrue(events.items([item("b#1"), item("a#1")]).isEmpty)
    }

    func testStatusChangeEmits() {
        var events = WebEvents()
        _ = events.items([item("a#1")])
        XCTAssertEqual(events.items([item("a#1", status: "in_progress")]).count, 1)
    }

    func testNoteChangeEmits() {
        var events = WebEvents()
        _ = events.items([item("a#1")])
        XCTAssertEqual(events.items([item("a#1", note: "fixed")]).count, 1)
    }

    func testProjectChangeEmits() {
        var events = WebEvents()
        _ = events.items([item("a#1")])
        XCTAssertEqual(events.items([item("a#1", project: "/work/app")]).count, 1)
    }

    func testNewItemEmits() {
        var events = WebEvents()
        _ = events.items([item("a#1")])
        let result = events.items([item("a#1"), item("b#1")])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].data["count"] as? Int, 2)
    }

    func testQuestionAddedAndAnsweredEmit() {
        var events = WebEvents()
        XCTAssertEqual(events.questions([]).count, 1)
        XCTAssertTrue(events.questions([]).isEmpty)
        let added = events.questions([question("q1")])
        XCTAssertEqual(added.map(\.name), ["questions.changed"])
        XCTAssertEqual(added[0].data["count"] as? Int, 1)
        XCTAssertTrue(events.questions([question("q1")]).isEmpty)
        let answered = events.questions([])
        XCTAssertEqual(answered.count, 1)
        XCTAssertEqual(answered[0].data["count"] as? Int, 0)
    }

    func testPhaseChangeEmits() {
        var events = WebEvents()
        let first = events.recording(phase: "idle", pointCount: 0)
        XCTAssertEqual(first.map(\.name), ["recording.changed"])
        XCTAssertEqual(first[0].data["phase"] as? String, "idle")
        XCTAssertTrue(events.recording(phase: "idle", pointCount: 0).isEmpty)
        let started = events.recording(phase: "recording", pointCount: 0)
        XCTAssertEqual(started.count, 1)
        XCTAssertEqual(started[0].data["phase"] as? String, "recording")
    }

    private func appStatus(running: Bool = true, sessions: Int = 1, microphone: Bool = true) -> AppStatus {
        AppStatus(mcpRunning: running, mcpPort: 6742, mcpText: "text", sessions: sessions, agents: ["claude"],
                  microphone: microphone, screenRecording: true, accessibility: true)
    }

    func testFirstStatusCallEmitsTheDictionary() {
        var events = WebEvents()
        let result = events.status(appStatus())
        XCTAssertEqual(result.map(\.name), ["status.changed"])
        XCTAssertEqual(result[0].data["mcpPort"] as? Int, 6742)
        XCTAssertEqual(result[0].data["sessions"] as? Int, 1)
        XCTAssertEqual(result[0].data["microphone"] as? Bool, true)
    }

    func testSameStatusDoesNotEmitAgain() {
        var events = WebEvents()
        _ = events.status(appStatus())
        XCTAssertTrue(events.status(appStatus()).isEmpty)
    }

    func testPermissionFlipEmits() {
        var events = WebEvents()
        _ = events.status(appStatus())
        let result = events.status(appStatus(microphone: false))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].data["microphone"] as? Bool, false)
    }

    func testMcpStartAndStopEmit() {
        var events = WebEvents()
        _ = events.status(appStatus(running: false))
        XCTAssertEqual(events.status(appStatus(running: true)).count, 1)
        XCTAssertEqual(events.status(appStatus(running: false)).count, 1)
    }

    func testSessionCountChangeEmits() {
        var events = WebEvents()
        _ = events.status(appStatus(sessions: 1))
        let result = events.status(appStatus(sessions: 2))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].data["sessions"] as? Int, 2)
    }

    func testPointCountChangeEmits() {
        var events = WebEvents()
        _ = events.recording(phase: "recording", pointCount: 0)
        let result = events.recording(phase: "recording", pointCount: 3)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].data["pointCount"] as? Int, 3)
    }
}
