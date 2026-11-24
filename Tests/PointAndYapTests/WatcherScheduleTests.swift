import XCTest
@testable import PointAndYap

/// What the floating watcher reads on each tick: items only inside the 30 second read window, questions every 5 seconds.
final class WatcherScheduleTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func reads(at seconds: TimeInterval, windowOpenedAt: Date?, lastQuestionCheck: Date? = nil,
                       needsBaseline: Bool = false, kitFloating: Bool = true) -> WatcherReads {
        WatcherSchedule.reads(now: start.addingTimeInterval(seconds), windowOpenedAt: windowOpenedAt,
                              lastQuestionCheck: lastQuestionCheck, needsBaseline: needsBaseline, kitFloating: kitFloating)
    }

    func testItemsAreReadInsideTheWindow() {
        XCTAssertTrue(reads(at: 0, windowOpenedAt: start).items)
        XCTAssertTrue(reads(at: 29, windowOpenedAt: start).items)
    }

    func testItemsAreNotReadAfterTheWindowEnds() {
        XCTAssertFalse(reads(at: 30, windowOpenedAt: start).items)
        XCTAssertFalse(reads(at: 300, windowOpenedAt: start).items)
    }

    func testItemsAreNotReadWhenNoWindowWasEverOpened() {
        XCTAssertFalse(reads(at: 5, windowOpenedAt: nil).items)
    }

    func testOpeningTheWindowAgainRestartsTheThirtySeconds() {
        let reopened = start.addingTimeInterval(40)
        XCTAssertFalse(reads(at: 45, windowOpenedAt: start).items)
        XCTAssertTrue(reads(at: 45, windowOpenedAt: reopened).items)
        XCTAssertTrue(reads(at: 69, windowOpenedAt: reopened).items)
        XCTAssertFalse(reads(at: 70, windowOpenedAt: reopened).items)
    }

    func testTheFirstTickAlwaysReadsQuestions() {
        XCTAssertTrue(reads(at: 0, windowOpenedAt: nil, lastQuestionCheck: nil).questions)
    }

    func testQuestionsAreReadEveryFiveSeconds() {
        XCTAssertFalse(reads(at: 1, windowOpenedAt: nil, lastQuestionCheck: start).questions)
        XCTAssertFalse(reads(at: 4, windowOpenedAt: nil, lastQuestionCheck: start).questions)
        XCTAssertTrue(reads(at: 5, windowOpenedAt: nil, lastQuestionCheck: start).questions)
        XCTAssertTrue(reads(at: 60, windowOpenedAt: nil, lastQuestionCheck: start).questions)
    }

    func testTheBaselineReadHappensOutsideTheWindow() {
        XCTAssertTrue(reads(at: 100, windowOpenedAt: nil, needsBaseline: true).items)
    }

    func testNothingIsReadWhileKitFloatingIsOff() {
        let result = reads(at: 0, windowOpenedAt: start, lastQuestionCheck: nil, needsBaseline: true, kitFloating: false)
        XCTAssertEqual(result, WatcherReads(items: false, questions: false))
    }
}
