import XCTest
@testable import PointAndYap

/// The queue shows the newest recording first, also for open items that have no state date yet.
@MainActor
final class NewestFirstTests: XCTestCase {
    private func openItem(session: String, at: Date? = nil) -> Item {
        Item(id: "\(session)#1", session: session, n: 1, title: "t", body: "", crops: [], status: "open", at: at)
    }

    func testTwoOpenItemsWithNoDateShowTheNewerRecordingFirst() {
        let older = openItem(session: "2026-11-26_093109")
        let newer = openItem(session: "2026-11-26_115202")
        let sorted = WebBridge.newestFirst([older, newer])
        XCTAssertEqual(sorted.map(\.id), ["2026-11-26_115202#1", "2026-11-26_093109#1"])
    }

    func testAnItemWithItsOwnDateKeepsUsingIt() {
        let now = Date()
        let finishedLater = openItem(session: "2026-11-26_093109", at: now)
        let finishedEarlier = openItem(session: "2026-11-26_115202", at: now.addingTimeInterval(-3600))
        let sorted = WebBridge.newestFirst([finishedEarlier, finishedLater])
        XCTAssertEqual(sorted.map(\.id), ["2026-11-26_093109#1", "2026-11-26_115202#1"])
    }
}
