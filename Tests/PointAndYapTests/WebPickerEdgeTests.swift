import XCTest
@testable import PointAndYap

/// T2: edges of the recording bridge (start then stop, the picking phase) and of the picker.changed event.
final class WebPickerEdgeTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override class func setUp() { _ = PointAndYapTests.root }

    override func setUp() {
        suiteName = "WebPickerEdgeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private final class Fake {
        var recording = RecordingSnapshot(phase: "idle", startedAt: nil, points: 0)
        var actions: [WebBridge.RecordingAction] = []
    }

    private func bridge(_ fake: Fake) -> WebBridge {
        WebBridge(defaults: defaults, loadItems: { [] },
                  controlRecording: { fake.actions.append($0) },
                  loadRecording: { fake.recording },
                  loadPicker: { nil },
                  answerPicker: { _ in false })
    }

    private func code(_ subject: WebBridge, _ method: String) throws -> String? {
        try T1Support.errorCode(subject.handle(message: ["id": 1, "method": method, "params": [:]]))
    }

    func testStopRightAfterStartIsBusyUntilTheAppReportsRecording() throws {
        let fake = Fake()
        let subject = bridge(fake)
        XCTAssertNil(try code(subject, "recording.start"))
        XCTAssertEqual(try code(subject, "recording.stop"), "busy")
        XCTAssertEqual(try code(subject, "recording.cancel"), "busy")
        XCTAssertEqual(fake.actions, [.start])
        fake.recording.phase = "recording"
        XCTAssertNil(try code(subject, "recording.stop"))
        XCTAssertEqual(fake.actions, [.start, .stop])
    }

    func testStartTwiceInARowBeforeTheAppChangesPhaseCallsTheClosureTwice() throws {
        let fake = Fake()
        let subject = bridge(fake)
        XCTAssertNil(try code(subject, "recording.start"))
        XCTAssertNil(try code(subject, "recording.start"))
        XCTAssertEqual(fake.actions, [.start, .start])
        fake.recording.phase = "recording"
        XCTAssertEqual(try code(subject, "recording.start"), "busy")
        XCTAssertEqual(fake.actions.count, 2)
    }

    func testStartWhileProcessingIsBusyAndLeavesNoAction() throws {
        let fake = Fake()
        fake.recording.phase = "processing"
        let subject = bridge(fake)
        XCTAssertEqual(try code(subject, "recording.start"), "busy")
        XCTAssertEqual(try code(subject, "recording.stop"), "busy")
        XCTAssertTrue(fake.actions.isEmpty)
        fake.recording.phase = "idle"
        XCTAssertNil(try code(subject, "recording.start"))
        XCTAssertEqual(fake.actions, [.start])
    }

    func testPickingShowsOnlyWhileIdleAndThePickerIsOpen() {
        let started = Date(timeIntervalSince1970: 50)
        let cases: [(AppState.Phase, Bool, String)] = [
            (.idle, true, "picking"), (.idle, false, "idle"),
            (.recording(started), true, "recording"), (.recording(started), false, "recording"),
            (.processing, true, "processing"), (.processing, false, "processing"),
        ]
        for (phase, pickerOpen, expected) in cases {
            let snapshot = WebHost.recordingSnapshot(phase: phase, pointCount: 2, pickerOpen: pickerOpen)
            XCTAssertEqual(snapshot.phase, expected, "\(phase) picker \(pickerOpen)")
            XCTAssertEqual(snapshot.points, 2)
        }
        XCTAssertNil(WebHost.recordingSnapshot(phase: .idle, pointCount: 0, pickerOpen: true).startedAt)
        XCTAssertNil(WebHost.recordingSnapshot(phase: .processing, pointCount: 0, pickerOpen: true).startedAt)
        XCTAssertEqual(WebHost.recordingSnapshot(phase: .recording(started), pointCount: 0, pickerOpen: true).startedAt, started)
    }

    func testPhaseNamesCoverEveryPhase() {
        XCTAssertEqual(WebHost.phaseName(.idle), "idle")
        XCTAssertEqual(WebHost.phaseName(.recording(Date())), "recording")
        XCTAssertEqual(WebHost.phaseName(.processing), "processing")
    }

    func testRecordingChangedEmitsForPickingThenIdle() {
        var events = WebEvents()
        XCTAssertEqual(events.recording(phase: "idle", pointCount: 0).count, 1)
        XCTAssertEqual(events.recording(phase: "picking", pointCount: 0).first?.data["phase"] as? String, "picking")
        XCTAssertTrue(events.recording(phase: "picking", pointCount: 0).isEmpty)
        XCTAssertEqual(events.recording(phase: "idle", pointCount: 0).count, 1)
    }

    private func snapshot(session: String?, countdown: Int?) -> PickerSnapshot {
        PickerSnapshot(session: session, choices: [PickerSnapshot.Choice(name: "backend", path: "/work/backend", key: 1, suggested: false)],
                       countdown: countdown)
    }

    func testPickerChangedEmitsThreeTimesForOpenCloseOpen() {
        var events = WebEvents()
        XCTAssertEqual(events.picker(nil).count, 1)
        var emitted = 0
        for _ in 0..<2 {
            let opened = events.picker(snapshot(session: "s1", countdown: 60))
            XCTAssertEqual(opened.count, 1)
            XCTAssertEqual(opened.first?.name, "picker.changed")
            XCTAssertEqual(opened.first?.data["open"] as? Bool, true)
            let closed = events.picker(nil)
            XCTAssertEqual(closed.count, 1)
            XCTAssertEqual(closed.first?.data["open"] as? Bool, false)
            emitted += opened.count + closed.count
        }
        let reopened = events.picker(snapshot(session: "s1", countdown: 60))
        emitted += reopened.count
        XCTAssertEqual(reopened.first?.data["open"] as? Bool, true)
        XCTAssertEqual(emitted, 5)
    }

    func testOpenCloseOpenWithoutAFirstClosedCallEmitsThreeTimes() {
        var events = WebEvents()
        let first = events.picker(snapshot(session: "s1", countdown: 60)).count
        let second = events.picker(nil).count
        let third = events.picker(snapshot(session: "s1", countdown: 60)).count
        XCTAssertEqual([first, second, third], [1, 1, 1])
    }

    func testCountdownAloneNeverEmits() {
        var events = WebEvents()
        XCTAssertEqual(events.picker(snapshot(session: "s1", countdown: 60)).count, 1)
        for seconds in stride(from: 59, through: 0, by: -1) {
            XCTAssertTrue(events.picker(snapshot(session: "s1", countdown: seconds)).isEmpty, "\(seconds)")
        }
        XCTAssertTrue(events.picker(snapshot(session: "s1", countdown: nil)).isEmpty)
        XCTAssertEqual(events.picker(nil).count, 1)
    }

    func testAPickerWithoutASessionHasNoSessionKey() {
        var events = WebEvents()
        let opened = events.picker(snapshot(session: nil, countdown: 60))
        XCTAssertEqual(opened.count, 1)
        XCTAssertNil(opened[0].data["session"])
        XCTAssertEqual(opened[0].data["open"] as? Bool, true)
    }
}
