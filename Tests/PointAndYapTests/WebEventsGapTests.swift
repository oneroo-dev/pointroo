import XCTest
@testable import PointAndYap

/// T1: the change detector sends nothing when nothing changed, one event per real change, and each kind on its own.
final class WebEventsGapTests: XCTestCase {
    private func item(_ id: String, status: String = "open", note: String? = nil, project: String? = nil, title: String = "Fix it") -> Item {
        var made = Item(id: id, session: "s", n: 1, title: title, body: "body", crops: [], status: status, at: nil)
        made.note = note
        made.project = project
        return made
    }

    private func question(_ id: String) -> Question {
        Question(id: id, project: "p", cwd: "/tmp", agent: "a", text: "Which?", choices: [], asked: Date(timeIntervalSince1970: 0))
    }

    private func status(running: Bool = true, port: Int = 6742, text: String = "text", sessions: Int = 1, agents: [String] = ["claude"],
                        microphone: Bool = true, screenRecording: Bool = true, accessibility: Bool = true) -> AppStatus {
        AppStatus(mcpRunning: running, mcpPort: port, mcpText: text, sessions: sessions, agents: agents,
                  microphone: microphone, screenRecording: screenRecording, accessibility: accessibility)
    }

    func testRepeatingTheSameSnapshotNeverEmitsAfterTheFirstCall() {
        var events = WebEvents()
        let items = [item("a#1"), item("b#1", status: "done")]
        let questions = [question("q1")]
        XCTAssertEqual(events.items(items).count, 1)
        XCTAssertEqual(events.questions(questions).count, 1)
        XCTAssertEqual(events.status(status()).count, 1)
        XCTAssertEqual(events.recording(phase: "idle", pointCount: 0).count, 1)
        for _ in 0..<5 {
            XCTAssertTrue(events.items(items).isEmpty)
            XCTAssertTrue(events.questions(questions).isEmpty)
            XCTAssertTrue(events.status(status()).isEmpty)
            XCTAssertTrue(events.recording(phase: "idle", pointCount: 0).isEmpty)
        }
    }

    func testEachRealItemChangeEmitsExactlyOnceAndTheSameSnapshotAfterItEmitsNothing() {
        var events = WebEvents()
        let steps = [[item("a#1")],
                     [item("a#1", status: "in_progress")],
                     [item("a#1", status: "done", note: "fixed")],
                     [item("a#1", status: "done", note: "fixed again")],
                     [item("a#1", status: "done", note: "fixed again", project: "/work/app")],
                     [item("a#1", status: "done", note: "fixed again", project: "/work/app"), item("b#1")],
                     [item("b#1")],
                     []]
        for (index, step) in steps.enumerated() {
            XCTAssertEqual(events.items(step).count, 1, "step \(index) is a real change")
            XCTAssertTrue(events.items(step).isEmpty, "step \(index) again is not")
        }
    }

    func testGoingBackToAnEarlierItemStateEmitsAgain() {
        var events = WebEvents()
        _ = events.items([item("a#1")])
        XCTAssertEqual(events.items([item("a#1", status: "done")]).count, 1)
        let back = events.items([item("a#1")])
        XCTAssertEqual(back.count, 1)
        XCTAssertEqual(back[0].data["open"] as? Int, 1)
    }

    func testAnItemEmitCarriesCountsThatFollowTheChange() {
        var events = WebEvents()
        _ = events.items([item("a#1"), item("b#1")])
        let started = events.items([item("a#1", status: "in_progress"), item("b#1")])
        XCTAssertEqual(started[0].data["count"] as? Int, 2)
        XCTAssertEqual(started[0].data["open"] as? Int, 1)
        XCTAssertEqual(started[0].data["inProgress"] as? Int, 1)
        let trashed = events.items([item("a#1", status: "in_progress"), item("b#1", status: "trashed")])
        XCTAssertEqual(trashed.count, 1)
        XCTAssertEqual(trashed[0].data["open"] as? Int, 0)
        XCTAssertEqual(trashed[0].data["inProgress"] as? Int, 1)
    }

    func testChangesTheItemSignatureDoesNotCoverEmitNothing() {
        var events = WebEvents()
        _ = events.items([item("a#1")])
        XCTAssertTrue(events.items([item("a#1", title: "A different title")]).isEmpty, "only id, status, note and project count")
    }

    func testOnlyTheChangedKindEmitsWhenSeveralDetectorsRun() {
        var events = WebEvents()
        _ = events.items([item("a#1")])
        _ = events.questions([])
        _ = events.status(status())
        _ = events.recording(phase: "idle", pointCount: 0)
        XCTAssertEqual(events.items([item("a#1", status: "done")]).map(\.name), ["items.changed"])
        XCTAssertTrue(events.questions([]).isEmpty)
        XCTAssertTrue(events.status(status()).isEmpty)
        XCTAssertTrue(events.recording(phase: "idle", pointCount: 0).isEmpty)
        XCTAssertEqual(events.questions([question("q1")]).map(\.name), ["questions.changed"])
        XCTAssertTrue(events.items([item("a#1", status: "done")]).isEmpty)
    }

    func testTheFirstCallOfEachKindEmitsEvenWhenAnotherKindRanBefore() {
        var events = WebEvents()
        XCTAssertEqual(events.items([]).map(\.name), ["items.changed"])
        XCTAssertEqual(events.questions([]).map(\.name), ["questions.changed"])
        XCTAssertEqual(events.status(status()).map(\.name), ["status.changed"])
        XCTAssertEqual(events.recording(phase: "idle", pointCount: 0).map(\.name), ["recording.changed"])
    }

    func testStatusChangedEmitsForEachPartOfTheStatusAndOnlyWhenItChanged() {
        var events = WebEvents()
        _ = events.status(status())
        let changes: [AppStatus] = [status(port: 6743), status(port: 6743, text: "other text"), status(port: 6743, text: "other text", agents: ["claude", "codex"]),
                                    status(running: false, port: 6743, text: "other text", agents: ["claude", "codex"]),
                                    status(running: false, port: 6743, text: "other text", agents: ["claude", "codex"], screenRecording: false),
                                    status(running: false, port: 6743, text: "other text", agents: ["claude", "codex"], screenRecording: false, accessibility: false)]
        for (index, changed) in changes.enumerated() {
            let emitted = events.status(changed)
            XCTAssertEqual(emitted.map(\.name), ["status.changed"], "change \(index)")
            XCTAssertEqual(emitted[0].data["mcpPort"] as? Int, changed.mcpPort)
            XCTAssertEqual(emitted[0].data["mcpText"] as? String, changed.mcpText)
            XCTAssertEqual(emitted[0].data["agents"] as? [String], changed.agents)
            XCTAssertTrue(events.status(changed).isEmpty, "change \(index) again is not a change")
        }
    }

    func testStatusGoingBackToAnEarlierValueEmitsAgain() {
        var events = WebEvents()
        _ = events.status(status(microphone: true))
        XCTAssertEqual(events.status(status(microphone: false)).count, 1)
        XCTAssertEqual(events.status(status(microphone: true)).count, 1)
        XCTAssertTrue(events.status(status(microphone: true)).isEmpty)
    }

    func testAnswerOrderOfQuestionsDoesNotMatterButADifferentSetDoes() {
        var events = WebEvents()
        _ = events.questions([question("q1"), question("q2")])
        XCTAssertTrue(events.questions([question("q2"), question("q1")]).isEmpty)
        let fewer = events.questions([question("q2")])
        XCTAssertEqual(fewer.count, 1)
        XCTAssertEqual(fewer[0].data["count"] as? Int, 1)
        XCTAssertEqual(events.questions([question("q2"), question("q3")]).count, 1, "one left and one came: the set changed")
    }

    func testRecordingEmitsOncePerChangeOfPhaseOrPointCountWithBothKeys() {
        var events = WebEvents()
        _ = events.recording(phase: "idle", pointCount: 0)
        let steps: [(String, Int)] = [("recording", 0), ("recording", 1), ("recording", 2), ("processing", 2), ("idle", 2), ("idle", 0)]
        for (phase, count) in steps {
            let emitted = events.recording(phase: phase, pointCount: count)
            XCTAssertEqual(emitted.count, 1, "\(phase) \(count)")
            XCTAssertEqual(emitted[0].name, "recording.changed")
            XCTAssertEqual(emitted[0].data["phase"] as? String, phase)
            XCTAssertEqual(emitted[0].data["pointCount"] as? Int, count)
            XCTAssertTrue(events.recording(phase: phase, pointCount: count).isEmpty, "\(phase) \(count) again")
        }
    }
}
