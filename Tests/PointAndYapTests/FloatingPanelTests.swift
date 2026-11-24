import XCTest
@testable import PointAndYap

/// The kit floating panels: the one decision (setting off keeps the SwiftUI path), the setting, the page's messages, where panels go,
/// the picker's keys and the done banner's hand-over.
@MainActor
final class FloatingPanelTests: XCTestCase {
    private let backend = Project(name: "backend", path: "/work/backend")
    private let web = Project(name: "web", path: "/work/web")
    private let docs = Project(name: "docs", path: "/work/docs")

    private var sleepers: [CheckedContinuation<Void, Never>] = []
    private var tasks: [Task<Project?, Never>] = []
    private var realMakePanel: (([Project], @escaping @MainActor (Project?) -> Void) -> PickerHandle)?

    override class func setUp() { _ = PointAndYapTests.root }

    override func setUp() {
        sleepers = []
        tasks = []
        realMakePanel = ProjectPicker.makePanel
        ProjectPicker.makePanel = { _, _ in PickerHandle(close: {}) }
        ProjectPicker.pause = { [unowned self] _ in
            await withCheckedContinuation { self.sleepers.append($0) }
        }
    }

    override func tearDown() {
        ProjectPicker.answer(nil)
        for sleeper in sleepers { sleeper.resume() }
        sleepers = []
        if let realMakePanel { ProjectPicker.makePanel = realMakePanel }
        ProjectPicker.pause = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        }
    }

    func testKitFloatingNeedsTheSettingAndTheBuiltScreens() {
        XCTAssertTrue(FloatingChoice.useKit(kitFloating: true, uiAvailable: true))
        XCTAssertFalse(FloatingChoice.useKit(kitFloating: true, uiAvailable: false))
        XCTAssertFalse(FloatingChoice.useKit(kitFloating: false, uiAvailable: true))
        XCTAssertFalse(FloatingChoice.useKit(kitFloating: false, uiAvailable: false))
    }

    func testKitFloatingSettingIsOffWhenNeverSet() throws {
        let key = try XCTUnwrap(WebBridge.allowedSettings.first { $0.key == "kitFloating" })
        guard case .flag(let defaultValue) = key.kind else { return XCTFail("kitFloating must be a flag") }
        XCTAssertFalse(defaultValue)
    }

    func testPageMessagesAreReadFromWhatTheWebViewPosts() {
        XCTAssertEqual(FloatingPageMessage.parse(["kind": "size", "width": 392, "height": 88.5]), .size(width: 392, height: 88.5))
        XCTAssertEqual(FloatingPageMessage.parse(["kind": "size", "width": 0, "height": 0]), .size(width: 0, height: 0))
        XCTAssertEqual(FloatingPageMessage.parse(["kind": "open", "itemId": "s#1"]), .open(itemId: "s#1"))
        XCTAssertNil(FloatingPageMessage.parse(["kind": "size", "width": 392]))
        XCTAssertNil(FloatingPageMessage.parse(["kind": "size", "width": -1, "height": 10]))
        XCTAssertNil(FloatingPageMessage.parse(["kind": "open", "itemId": ""]))
        XCTAssertNil(FloatingPageMessage.parse(["kind": "other"]))
        XCTAssertNil(FloatingPageMessage.parse([:]))
    }

    func testPanelsGoToTheirPlaceInsideTheVisibleArea() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let size = NSSize(width: 400, height: 100)
        XCTAssertEqual(FloatingPlacement.origin(route: .pill, size: size, visible: visible), NSPoint(x: 300, y: 700))
        XCTAssertEqual(FloatingPlacement.origin(route: .picker, size: size, visible: visible), NSPoint(x: 300, y: 656))
        XCTAssertEqual(FloatingPlacement.origin(route: .notice, size: size, visible: visible), NSPoint(x: 600, y: 700))
    }

    func testResizingKeepsTheTopLeftCorner() {
        let frame = NSRect(x: 50, y: 600, width: 392, height: 100)
        let resized = FloatingPlacement.resized(frame: frame, to: NSSize(width: 392, height: 160))
        XCTAssertEqual(resized, NSRect(x: 50, y: 540, width: 392, height: 160))
        XCTAssertEqual(resized.maxY, frame.maxY)
    }

    func testRoutesAreTheWordsThePageKnows() {
        XCTAssertEqual([FloatingRoute.pill, .picker, .notice].map(\.rawValue), ["pill", "picker", "notice"])
    }

    private func openPicker(_ projects: [Project]) async -> Task<Project?, Never> {
        let task = Task { @MainActor in await ProjectPicker.ask(projects, session: "s1", suggested: nil) }
        tasks.append(task)
        let expected = tasks.count
        var turns = 0
        while (ProjectPicker.snapshot() == nil || sleepers.count < expected) && turns < 200 {
            await Task.yield()
            turns += 1
        }
        return task
    }

    func testANumberKeyPicksTheProjectInThatPlace() async {
        let task = await openPicker([backend, web, docs])
        XCTAssertTrue(ProjectPicker.answerKey(keyCode: 19, characters: "2"))
        let picked = await task.value
        XCTAssertEqual(picked, web)
        XCTAssertNil(ProjectPicker.snapshot())
    }

    func testEscSkipsTheOpenPicker() async {
        let task = await openPicker([backend, web])
        XCTAssertTrue(ProjectPicker.answerKey(keyCode: 53, characters: "\u{1B}"))
        let picked = await task.value
        XCTAssertNil(picked)
    }

    func testOtherKeysAndNumbersWithNoProjectAreLeftAlone() async {
        let task = await openPicker([backend, web])
        XCTAssertFalse(ProjectPicker.answerKey(keyCode: 0, characters: "a"))
        XCTAssertFalse(ProjectPicker.answerKey(keyCode: 21, characters: "3"))
        XCTAssertFalse(ProjectPicker.answerKey(keyCode: 29, characters: "0"))
        XCTAssertNotNil(ProjectPicker.snapshot())
        XCTAssertTrue(ProjectPicker.answer(nil))
        _ = await task.value
    }

    func testKeysDoNothingWhenNoPickerIsOpen() {
        XCTAssertFalse(ProjectPicker.answerKey(keyCode: 53, characters: nil))
        XCTAssertFalse(ProjectPicker.answerKey(keyCode: 18, characters: "1"))
    }

    func testKitNoticeIsNotMarkedSeenWhenItShowsAndTheBannerOpensNoSwiftUIPanel() {
        var seen: [String] = []
        var presented: [BannerNotice] = []
        let banner = DoneBanner()
        banner.markSeen = { seen.append($0) }
        banner.presentsOutside = { notice in
            presented.append(notice)
            return true
        }
        banner.show(project: "backend", note: "done", itemId: "s#1") {}
        XCTAssertEqual(presented.map(\.itemId), ["s#1"])
        XCTAssertEqual(seen, [], "the kit card marks it seen when it is dealt with")
    }
}
