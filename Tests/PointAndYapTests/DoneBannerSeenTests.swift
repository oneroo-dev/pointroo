import XCTest
@testable import PointAndYap

@MainActor
final class DoneBannerSeenTests: XCTestCase {
    private var folder: URL!
    private var seen: [String] = []

    override class func setUp() { _ = PointAndYapTests.root }

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("banner-seen-\(UUID().uuidString)")
        seen = []
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeBanner() -> DoneBanner {
        let banner = DoneBanner()
        banner.opensPanel = false
        banner.markSeen = { [weak self] id in self?.seen.append(id) }
        return banner
    }

    private func item(_ id: String) -> Item {
        var made = Item(id: id, session: "s", n: 1, title: "Fix it", body: "body", crops: [], status: "done",
                        at: Date(timeIntervalSince1970: 100))
        made.by = "claude"
        return made
    }

    func testQueueKeepsItemId() {
        var queue = BannerQueue()
        queue.add(BannerNotice(project: "backend", note: "done", itemId: "s#1"))
        XCTAssertEqual(queue.next(paused: false)?.itemId, "s#1")
    }

    func testNoticeForItemWithoutCropsCarriesItemId() async {
        let notice = await AfterShot.notice(item: item("s#7"), project: "backend")
        XCTAssertEqual(notice.itemId, "s#7")
    }

    func testShownBannerMarksItemSeenOnce() {
        let banner = makeBanner()
        banner.show(project: "backend", note: "done", itemId: "s#1") {}
        XCTAssertEqual(seen, ["s#1"])
    }

    func testBannerWithoutItemIdDoesNotMarkSeen() {
        let banner = makeBanner()
        banner.show(project: "backend", note: "done") {}
        XCTAssertEqual(seen, [])
    }

    func testPausedBannerMarksSeenOnlyAfterUnpause() {
        let banner = makeBanner()
        banner.paused = true
        banner.show(project: "backend", note: "done", itemId: "s#2") {}
        XCTAssertEqual(seen, [])
        banner.paused = false
        XCTAssertEqual(seen, ["s#2"])
    }

    func testSeenBannerIsNoLongerAnUnseenNotice() {
        let store = NoticeStore(folder: folder)
        let banner = makeBanner()
        banner.markSeen = { id in _ = store.markSeen([id]) }
        let done = item("s#3")
        XCTAssertTrue(Notices.isUnseenDone(done, seen: Set(store.seenIds())))
        banner.show(project: "backend", note: "done", itemId: done.id) {}
        XCTAssertFalse(Notices.isUnseenDone(done, seen: Set(store.seenIds())))
    }
}
