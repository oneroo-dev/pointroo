import XCTest
@testable import PointAndYap

/// T6: the read-window notification (posted by Router.writeRoute and AppState.stop) really opens the window in a started watcher.
/// The clock is given, and the one second timer is off, so nothing reads the disk and nothing waits for a tick.
@MainActor
final class FloatingWatcherWiringTests: XCTestCase {
    override class func setUp() { _ = PointAndYapTests.root }

    private let openedAt = Date(timeIntervalSince1970: 1_000_000)

    private func makeWatcher() -> FloatingWatcher {
        FloatingWatcher(onSent: { _ in }, onQuestion: {}, now: { [openedAt] in openedAt }, usesTimer: false)
    }

    private func waitForWindow(_ watcher: FloatingWatcher) async {
        var turns = 0
        while watcher.windowOpenedAt == nil && turns < 200 {
            try? await Task.sleep(nanoseconds: 10_000_000)
            turns += 1
        }
    }

    func testAStartedWatcherOpensTheReadWindowOnTheNotification() async {
        let watcher = makeWatcher()
        watcher.start()
        defer { watcher.stop() }
        XCTAssertNil(watcher.windowOpenedAt)
        FloatingWatcher.openReadWindow()
        await waitForWindow(watcher)
        XCTAssertEqual(watcher.windowOpenedAt, openedAt)
        let reads = WatcherSchedule.reads(now: openedAt.addingTimeInterval(5), windowOpenedAt: watcher.windowOpenedAt,
                                          lastQuestionCheck: openedAt, kitFloating: true)
        XCTAssertTrue(reads.items)
    }

    func testWritingARouteOpensTheReadWindow() async throws {
        let dir = try T1Support.makeSession("2026-11-28_watcher-window-route", project: "/work/backend")
        defer { try? FileManager.default.removeItem(at: dir) }
        let watcher = makeWatcher()
        watcher.start()
        defer { watcher.stop() }
        Router.writeRoute(RouteInfo(project: "backend", path: "/work/backend", how: "said"), to: dir)
        await waitForWindow(watcher)
        XCTAssertEqual(watcher.windowOpenedAt, openedAt)
    }

    func testAWatcherThatWasNotStartedIgnoresTheNotification() async {
        let watcher = makeWatcher()
        FloatingWatcher.openReadWindow()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(watcher.windowOpenedAt)
    }

    func testAStoppedWatcherIgnoresTheNotification() async {
        let watcher = makeWatcher()
        watcher.start()
        watcher.stop()
        FloatingWatcher.openReadWindow()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(watcher.windowOpenedAt)
    }
}
