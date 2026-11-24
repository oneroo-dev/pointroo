import XCTest
@testable import PointAndYap

/// The "open this item" request for the kit main window: sent at once when the page is ready, kept (once) when it is not.
final class PendingFocusTests: XCTestCase {
    func testARequestOnAReadyPageIsSentNowAndNothingWaits() {
        var focus = PendingFocus()
        XCTAssertEqual(focus.request("s1#2", pageReady: true), "s1#2")
        XCTAssertNil(focus.waitingId)
        XCTAssertNil(focus.pageBecameReady())
    }

    func testARequestBeforeTheLoadIsKeptAndSentOnceAfterIt() {
        var focus = PendingFocus()
        XCTAssertNil(focus.request("s1#2", pageReady: false))
        XCTAssertEqual(focus.waitingId, "s1#2")
        XCTAssertEqual(focus.pageBecameReady(), "s1#2")
        XCTAssertNil(focus.pageBecameReady())
    }

    func testANewerWaitingRequestReplacesTheOlderOne() {
        var focus = PendingFocus()
        _ = focus.request("old#1", pageReady: false)
        _ = focus.request("new#1", pageReady: false)
        XCTAssertEqual(focus.pageBecameReady(), "new#1")
    }

    func testAReadyRequestClearsAWaitingOne() {
        var focus = PendingFocus()
        _ = focus.request("old#1", pageReady: false)
        XCTAssertEqual(focus.request("new#1", pageReady: true), "new#1")
        XCTAssertNil(focus.pageBecameReady())
    }

    func testTheEventIsItemFocusWithTheId() {
        let event = PendingFocus.event(id: "s1#2")
        XCTAssertEqual(event.name, "item.focus")
        XCTAssertEqual(event.data["id"] as? String, "s1#2")
        XCTAssertEqual(event.data.count, 1)
    }
}
