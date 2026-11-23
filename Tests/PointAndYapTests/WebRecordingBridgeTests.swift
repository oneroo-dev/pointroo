import XCTest
@testable import PointAndYap

/// R26: recording.* and picker.* bridge methods and the picker.changed event, with injected closures and no app state.
final class WebRecordingBridgeTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override class func setUp() { _ = PointAndYapTests.root }

    override func setUp() {
        suiteName = "WebRecordingBridgeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private final class Fake {
        var recording = RecordingSnapshot(phase: "idle", startedAt: nil, points: 0)
        var actions: [WebBridge.RecordingAction] = []
        var picker: PickerSnapshot?
        var answers: [String?] = []

        func answer(_ path: String?) -> Bool {
            guard picker != nil else { return false }
            picker = nil
            answers.append(path)
            return true
        }
    }

    private let backend = PickerSnapshot.Choice(name: "backend", path: "/work/backend", key: 1, suggested: true)
    private let web = PickerSnapshot.Choice(name: "web", path: "/work/web", key: 2, suggested: false)

    private func openPicker(_ fake: Fake) {
        fake.picker = PickerSnapshot(session: "2026-11-24_10-00-00", choices: [backend, web], countdown: 42)
    }

    private func bridge(_ fake: Fake) -> WebBridge {
        WebBridge(defaults: defaults, loadItems: { [] },
                  controlRecording: { fake.actions.append($0) },
                  loadRecording: { fake.recording },
                  loadPicker: { fake.picker },
                  answerPicker: { fake.answer($0) })
    }

    private func code(_ subject: WebBridge, _ method: String, _ params: [String: Any] = [:]) throws -> String? {
        try T1Support.errorCode(subject.handle(message: ["id": 1, "method": method, "params": params]))
    }

    private func result(_ subject: WebBridge, _ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        let reply = try T1Support.replyObject(subject.handle(message: ["id": 1, "method": method, "params": params]))
        return try XCTUnwrap(reply["result"] as? [String: Any], "\(reply)")
    }

    func testStartWhileIdleCallsTheClosure() throws {
        let fake = Fake()
        XCTAssertEqual(try result(bridge(fake), "recording.start")["started"] as? Bool, true)
        XCTAssertEqual(fake.actions, [.start])
    }

    func testStartWhileThePickerIsOpenIsAllowed() throws {
        let fake = Fake()
        fake.recording.phase = "picking"
        XCTAssertEqual(try result(bridge(fake), "recording.start")["started"] as? Bool, true)
        XCTAssertEqual(fake.actions, [.start])
    }

    func testStartWhileRecordingOrProcessingIsBusy() throws {
        for phase in ["recording", "processing"] {
            let fake = Fake()
            fake.recording.phase = phase
            XCTAssertEqual(try code(bridge(fake), "recording.start"), "busy", phase)
            XCTAssertTrue(fake.actions.isEmpty)
        }
    }

    func testStopAndCancelWhileRecordingCallTheClosure() throws {
        let fake = Fake()
        fake.recording.phase = "recording"
        let subject = bridge(fake)
        XCTAssertEqual(try result(subject, "recording.stop")["stopped"] as? Bool, true)
        XCTAssertEqual(try result(subject, "recording.cancel")["cancelled"] as? Bool, true)
        XCTAssertEqual(fake.actions, [.stop, .cancel])
    }

    func testStopAndCancelWhenNotRecordingAreBusy() throws {
        for phase in ["idle", "processing", "picking"] {
            let fake = Fake()
            fake.recording.phase = phase
            let subject = bridge(fake)
            XCTAssertEqual(try code(subject, "recording.stop"), "busy", phase)
            XCTAssertEqual(try code(subject, "recording.cancel"), "busy", phase)
            XCTAssertTrue(fake.actions.isEmpty)
        }
    }

    func testRecordingMethodsAreNotAvailableWithoutClosures() throws {
        let subject = WebBridge(defaults: defaults, loadItems: { [] })
        for method in ["recording.start", "recording.stop", "recording.cancel", "recording.get", "picker.get", "picker.skip"] {
            XCTAssertEqual(try code(subject, method), "not_available", method)
        }
        XCTAssertEqual(try code(subject, "picker.pick", ["path": "/work/backend"]), "not_available")
    }

    func testRecordingGetIdle() throws {
        let reply = try result(bridge(Fake()), "recording.get")
        XCTAssertEqual(reply["phase"] as? String, "idle")
        XCTAssertEqual(reply["points"] as? Int, 0)
        XCTAssertNil(reply["startedAt"])
        XCTAssertNil(reply["words"])
    }

    func testRecordingGetWhileRecordingHasStartAndWords() throws {
        let fake = Fake()
        fake.recording = RecordingSnapshot(phase: "recording", startedAt: Date(timeIntervalSince1970: 1_800_000_000), points: 3,
                                           words: ["fix", "this"])
        let reply = try result(bridge(fake), "recording.get")
        XCTAssertEqual(reply["phase"] as? String, "recording")
        XCTAssertEqual(reply["points"] as? Int, 3)
        XCTAssertEqual(reply["startedAt"] as? String, ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertEqual(reply["words"] as? [String], ["fix", "this"])
    }

    func testSnapshotOfAppPhaseUsesPickingOnlyWhenIdle() {
        let started = Date(timeIntervalSince1970: 10)
        XCTAssertEqual(WebHost.recordingSnapshot(phase: .idle, pointCount: 0, pickerOpen: true).phase, "picking")
        XCTAssertEqual(WebHost.recordingSnapshot(phase: .idle, pointCount: 0, pickerOpen: false).phase, "idle")
        XCTAssertEqual(WebHost.recordingSnapshot(phase: .processing, pointCount: 0, pickerOpen: true).phase, "processing")
        let recording = WebHost.recordingSnapshot(phase: .recording(started), pointCount: 4, pickerOpen: false)
        XCTAssertEqual(recording.phase, "recording")
        XCTAssertEqual(recording.startedAt, started)
        XCTAssertEqual(recording.points, 4)
    }

    func testPickerGetClosedAndOpen() throws {
        let fake = Fake()
        let subject = bridge(fake)
        let closed = try result(subject, "picker.get")
        XCTAssertEqual(closed["open"] as? Bool, false)
        XCTAssertNil(closed["choices"])
        openPicker(fake)
        let open = try result(subject, "picker.get")
        XCTAssertEqual(open["open"] as? Bool, true)
        XCTAssertEqual(open["session"] as? String, "2026-11-24_10-00-00")
        XCTAssertEqual(open["countdown"] as? Int, 42)
        let choices = try XCTUnwrap(open["choices"] as? [[String: Any]])
        XCTAssertEqual(choices.count, 2)
        XCTAssertEqual(choices[0]["name"] as? String, "backend")
        XCTAssertEqual(choices[0]["path"] as? String, "/work/backend")
        XCTAssertEqual(choices[0]["key"] as? Int, 1)
        XCTAssertEqual(choices[0]["suggested"] as? Bool, true)
        XCTAssertEqual(choices[1]["suggested"] as? Bool, false)
    }

    func testPickAnswersWithThePathOnce() throws {
        let fake = Fake()
        openPicker(fake)
        let subject = bridge(fake)
        XCTAssertEqual(try result(subject, "picker.pick", ["path": "/work/web"])["picked"] as? Bool, true)
        XCTAssertEqual(fake.answers, ["/work/web"])
        XCTAssertEqual(try code(subject, "picker.pick", ["path": "/work/web"]), "not_found")
        XCTAssertEqual(fake.answers, ["/work/web"])
    }

    func testPickRefusals() throws {
        let fake = Fake()
        let subject = bridge(fake)
        XCTAssertEqual(try code(subject, "picker.pick", ["path": "/work/web"]), "not_found")
        openPicker(fake)
        XCTAssertEqual(try code(subject, "picker.pick", ["path": "/work/other"]), "bad_params")
        let wrongPaths: [Any] = [5, true, "", NSNull(), ["a"]]
        for wrong in wrongPaths {
            XCTAssertEqual(try code(subject, "picker.pick", ["path": wrong]), "bad_params")
        }
        XCTAssertEqual(try code(subject, "picker.pick"), "bad_params")
        XCTAssertTrue(fake.answers.isEmpty)
        XCTAssertNotNil(fake.picker)
    }

    func testSkipAnswersWithNilOnce() throws {
        let fake = Fake()
        openPicker(fake)
        let subject = bridge(fake)
        XCTAssertEqual(try result(subject, "picker.skip")["skipped"] as? Bool, true)
        XCTAssertEqual(fake.answers.count, 1)
        XCTAssertNil(fake.answers[0])
        XCTAssertEqual(try code(subject, "picker.skip"), "not_found")
        XCTAssertEqual(fake.answers.count, 1)
    }

    func testSkipWithNoPickerIsNotFound() throws {
        XCTAssertEqual(try code(bridge(Fake()), "picker.skip"), "not_found")
    }

    func testPickerChangedEmitsOncePerOpenAndClose() {
        var events = WebEvents()
        let snapshot = PickerSnapshot(session: "s1", choices: [backend], countdown: 60)
        let first = events.picker(nil)
        XCTAssertEqual(first.map(\.name), ["picker.changed"])
        XCTAssertEqual(first[0].data["open"] as? Bool, false)
        XCTAssertTrue(events.picker(nil).isEmpty)
        let opened = events.picker(snapshot)
        XCTAssertEqual(opened.map(\.name), ["picker.changed"])
        XCTAssertEqual(opened[0].data["open"] as? Bool, true)
        XCTAssertEqual(opened[0].data["session"] as? String, "s1")
        var later = snapshot
        later.countdown = 30
        XCTAssertTrue(events.picker(later).isEmpty)
        let closed = events.picker(nil)
        XCTAssertEqual(closed.count, 1)
        XCTAssertEqual(closed[0].data["open"] as? Bool, false)
        XCTAssertNil(closed[0].data["session"])
        XCTAssertTrue(events.picker(nil).isEmpty)
    }
}
