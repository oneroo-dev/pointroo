import XCTest
@testable import PointAndYap

final class DoneNoticeTests: XCTestCase {
    private func item(_ session: String, _ n: Int, _ status: String, by: String? = "claude", note: String? = nil) -> Item {
        Item(id: "\(session)#\(n)", session: session, n: n, title: "title \(n)", body: "", crops: [],
             status: status, at: nil, by: by, note: note)
    }

    func testCountsOpenWorkingAndDoneItems() {
        let items = [item("a", 1, "open"), item("a", 2, "in_progress"), item("b", 1, "done"), item("c", 1, "open")]
        XCTAssertEqual(QueueStatus.counts(items), QueueCounts(open: 2, working: 1, done: 1))
    }

    func testNoStatusTitleWhenNothingIsOpenOrWorking() {
        XCTAssertEqual(QueueStatus.statusTitle(QueueCounts(open: 0, working: 0, done: 5)), "")
    }

    func testStatusTitleWithWorkingAndWaiting() {
        XCTAssertEqual(QueueStatus.statusTitle(QueueCounts(open: 2, working: 1, done: 0)), "1 working, 2 waiting")
        XCTAssertEqual(QueueStatus.statusTitle(QueueCounts(open: 0, working: 3, done: 0)), "3 working")
        XCTAssertEqual(QueueStatus.statusTitle(QueueCounts(open: 1, working: 0, done: 0)), "1 waiting")
    }

    func testSecondItemOfASessionFinishingIsNoticed() {
        let before = ["s#1": "done", "s#2": "in_progress"]
        let now = [item("s", 1, "done"), item("s", 2, "done", note: "fixed")]
        XCTAssertEqual(QueueStatus.newlyDone(before: before, items: now).map(\.id), ["s#2"])
    }

    func testItemsTheUserMarkedDoneAreIgnored() {
        let before = ["s#1": "open"]
        let now = [item("s", 1, "done", by: "you")]
        XCTAssertTrue(QueueStatus.newlyDone(before: before, items: now).isEmpty)
    }

    func testFirstPollOnlyRecords() {
        let now = [item("s", 1, "done"), item("s", 2, "done")]
        XCTAssertTrue(QueueStatus.newlyDone(before: [:], items: now).isEmpty)
    }

    func testAnItemAlreadyDoneIsNotRepeated() {
        XCTAssertTrue(QueueStatus.newlyDone(before: ["s#1": "done"], items: [item("s", 1, "done")]).isEmpty)
    }

    func testStatusByIDKeysEveryItem() {
        let map = QueueStatus.statusByID([item("s", 1, "open"), item("s", 2, "done")])
        XCTAssertEqual(map, ["s#1": "open", "s#2": "done"])
    }

    func testBannersShowOneAtATimeInOrder() {
        var queue = BannerQueue()
        queue.add(BannerNotice(project: "a", note: "one"))
        queue.add(BannerNotice(project: "b", note: "two"))
        XCTAssertEqual(queue.next(paused: false)?.note, "one")
        XCTAssertNil(queue.next(paused: false), "one is still showing")
        queue.finished()
        XCTAssertEqual(queue.next(paused: false)?.note, "two")
    }

    func testBannersWaitWhileRecordingAndShowAfter() {
        var queue = BannerQueue()
        queue.add(BannerNotice(project: "a", note: "one"))
        XCTAssertNil(queue.next(paused: true))
        XCTAssertEqual(queue.next(paused: false)?.note, "one")
    }
}
