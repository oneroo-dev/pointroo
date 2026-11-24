import XCTest
@testable import PointAndYap

/// T2: the project picker's state (snapshot, answer, timeout) with a fake window, a fake clock and a fake sleep.
@MainActor
final class ProjectPickerTests: XCTestCase {
    private let backend = Project(name: "backend", path: "/work/backend")
    private let web = Project(name: "web", path: "/work/web")
    private let docs = Project(name: "docs", path: "/work/docs")

    private var now = Date(timeIntervalSince1970: 1_800_000_000)
    private var closedWindows = 0
    private var madeWindows = 0
    private var sleepers: [CheckedContinuation<Void, Never>] = []
    private var tasks: [Task<Project?, Never>] = []

    private var realMakePanel: (([Project], @escaping @MainActor (Project?) -> Void) -> PickerHandle)?

    override func setUp() {
        realMakePanel = ProjectPicker.makePanel
        now = Date(timeIntervalSince1970: 1_800_000_000)
        closedWindows = 0
        madeWindows = 0
        sleepers = []
        tasks = []
        ProjectPicker.clock = { [unowned self] in self.now }
        ProjectPicker.makePanel = { [unowned self] _, _ in
            self.madeWindows += 1
            return PickerHandle(close: { self.closedWindows += 1 })
        }
        ProjectPicker.pause = { [unowned self] _ in
            await withCheckedContinuation { self.sleepers.append($0) }
        }
    }

    override func tearDown() {
        ProjectPicker.answer(nil)
        for sleeper in sleepers { sleeper.resume() }
        sleepers = []
        ProjectPicker.clock = { Date() }
        if let realMakePanel { ProjectPicker.makePanel = realMakePanel }
        ProjectPicker.pause = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        }
    }

    private func openPicker(_ projects: [Project], session: String? = "s1", suggested: String? = nil) async -> Task<Project?, Never> {
        let task = Task { @MainActor in await ProjectPicker.ask(projects, session: session, suggested: suggested) }
        tasks.append(task)
        let expected = tasks.count
        var turns = 0
        while (ProjectPicker.snapshot() == nil || sleepers.count < expected) && turns < 200 {
            await Task.yield()
            turns += 1
        }
        return task
    }

    func testSnapshotIsNilWhenNoPickerIsOpen() {
        XCTAssertNil(ProjectPicker.snapshot())
        XCTAssertNil(ProjectPicker.snapshotProject(path: "/work/backend"))
        XCTAssertFalse(ProjectPicker.answer(backend))
    }

    func testChoicesComeInKeyOrderWithTheSuggestedOneMarked() async throws {
        _ = await openPicker([backend, web, docs], session: "2026-11-24_10-00-00", suggested: "/work/web")
        let snapshot = try XCTUnwrap(ProjectPicker.snapshot())
        XCTAssertEqual(snapshot.session, "2026-11-24_10-00-00")
        XCTAssertEqual(snapshot.choices.map(\.name), ["backend", "web", "docs"])
        XCTAssertEqual(snapshot.choices.map(\.key), [1, 2, 3])
        XCTAssertEqual(snapshot.choices.map(\.path), ["/work/backend", "/work/web", "/work/docs"])
        XCTAssertEqual(snapshot.choices.map(\.suggested), [false, true, false])
        XCTAssertEqual(madeWindows, 1)
    }

    func testNoSuggestionMarksNothing() async throws {
        _ = await openPicker([backend, web])
        let snapshot = try XCTUnwrap(ProjectPicker.snapshot())
        XCTAssertEqual(snapshot.choices.map(\.suggested), [false, false])
    }

    func testOnlyTheFirstNineProjectsAreShown() async throws {
        let many = (1...12).map { Project(name: "p\($0)", path: "/work/p\($0)") }
        _ = await openPicker(many)
        let snapshot = try XCTUnwrap(ProjectPicker.snapshot())
        XCTAssertEqual(snapshot.choices.count, 9)
        XCTAssertEqual(snapshot.choices.last?.key, 9)
        XCTAssertNil(ProjectPicker.snapshotProject(path: "/work/p10"))
    }

    func testCountdownGoesDownAndNeverBelowZero() async throws {
        _ = await openPicker([backend])
        XCTAssertEqual(ProjectPicker.snapshot()?.countdown, ProjectPicker.timeoutSeconds)
        now = now.addingTimeInterval(10)
        XCTAssertEqual(ProjectPicker.snapshot()?.countdown, ProjectPicker.timeoutSeconds - 10)
        now = now.addingTimeInterval(49.5)
        XCTAssertEqual(ProjectPicker.snapshot()?.countdown, 1)
        now = now.addingTimeInterval(0.5)
        XCTAssertEqual(ProjectPicker.snapshot()?.countdown, 0)
        now = now.addingTimeInterval(500)
        XCTAssertEqual(ProjectPicker.snapshot()?.countdown, 0)
    }

    func testAnswerResolvesOnceAndClosesTheWindow() async {
        let task = await openPicker([backend, web])
        XCTAssertTrue(ProjectPicker.answer(web))
        XCTAssertFalse(ProjectPicker.answer(backend))
        let picked = await task.value
        XCTAssertEqual(picked, web)
        XCTAssertEqual(closedWindows, 1)
        XCTAssertNil(ProjectPicker.snapshot())
        XCTAssertNil(ProjectPicker.snapshotProject(path: "/work/web"))
    }

    func testAnswerNilSkips() async {
        let task = await openPicker([backend])
        XCTAssertTrue(ProjectPicker.answer(nil))
        let picked = await task.value
        XCTAssertNil(picked)
        XCTAssertFalse(ProjectPicker.answer(nil))
    }

    func testTimeoutSkipsAndALatePickIsFalse() async {
        let task = await openPicker([backend, web])
        XCTAssertEqual(sleepers.count, 1)
        sleepers.removeFirst().resume()
        let picked = await task.value
        XCTAssertNil(picked)
        XCTAssertEqual(closedWindows, 1)
        XCTAssertNil(ProjectPicker.snapshot())
        XCTAssertFalse(ProjectPicker.answer(web))
    }

    func testTimeoutOfAnAnsweredPickerDoesNotSkipTheNextOne() async {
        let first = await openPicker([backend])
        XCTAssertTrue(ProjectPicker.answer(backend))
        let firstPicked = await first.value
        XCTAssertEqual(firstPicked, backend)
        let second = await openPicker([web])
        XCTAssertEqual(sleepers.count, 2)
        sleepers.removeFirst().resume()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNotNil(ProjectPicker.snapshot())
        XCTAssertTrue(ProjectPicker.answer(web))
        let secondPicked = await second.value
        XCTAssertEqual(secondPicked, web)
        XCTAssertEqual(madeWindows, 2)
        XCTAssertEqual(closedWindows, 2)
    }

    func testSnapshotProjectFindsByFolderAndNilForAnUnknownPath() async throws {
        _ = await openPicker([backend, web])
        XCTAssertEqual(ProjectPicker.snapshotProject(path: "/work/web"), web)
        XCTAssertEqual(ProjectPicker.snapshotProject(path: "/work/web/"), web)
        XCTAssertNil(ProjectPicker.snapshotProject(path: "/work/elsewhere"))
        XCTAssertNil(ProjectPicker.snapshotProject(path: ""))
        XCTAssertNil(ProjectPicker.snapshotProject(path: "/work"))
    }
}
