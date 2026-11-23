import XCTest
@testable import PointAndYap

/// R7, hold Control to talk: the pure Control gesture machine, fed with explicit times.
final class KeyGestureTests: XCTestCase {
    override class func setUp() { _ = PointAndYapTests.root }

    func testDoubleTapTogglesWithHoldToTalkOff() {
        var gesture = KeyGesture()
        XCTAssertEqual(gesture.controlDown(at: 0, holdToTalk: false), [])
        XCTAssertEqual(gesture.controlUp(at: 0.1), [])
        XCTAssertEqual(gesture.controlDown(at: 0.2, holdToTalk: false), [])
        XCTAssertEqual(gesture.controlUp(at: 0.3), [.toggle])
    }

    func testDoubleTapTogglesWithHoldToTalkOn() {
        var gesture = KeyGesture()
        _ = gesture.controlDown(at: 0, holdToTalk: true)
        XCTAssertEqual(gesture.controlUp(at: 0.1), [])
        _ = gesture.controlDown(at: 0.2, holdToTalk: true)
        XCTAssertEqual(gesture.controlUp(at: 0.3), [.toggle])
    }

    func testTapsTooFarApartDoNotToggle() {
        var gesture = KeyGesture()
        _ = gesture.controlDown(at: 0, holdToTalk: false)
        _ = gesture.controlUp(at: 0.1)
        _ = gesture.controlDown(at: 0.6, holdToTalk: false)
        XCTAssertEqual(gesture.controlUp(at: 0.7), [])
    }

    func testHoldForHalfASecondAloneStartsAndReleaseEnds() {
        var gesture = KeyGesture()
        _ = gesture.controlDown(at: 10, holdToTalk: true)
        XCTAssertEqual(gesture.holdElapsed(at: 10.5), [.holdStart])
        XCTAssertTrue(gesture.isHolding)
        XCTAssertEqual(gesture.controlUp(at: 12), [.holdEnd])
        XCTAssertFalse(gesture.isHolding)
    }

    func testHoldDoesNotStartWithHoldToTalkOff() {
        var gesture = KeyGesture()
        _ = gesture.controlDown(at: 0, holdToTalk: false)
        XCTAssertEqual(gesture.holdElapsed(at: 0.5), [])
        XCTAssertEqual(gesture.controlUp(at: 2), [])
    }

    func testHoldDoesNotStartBeforeHalfASecond() {
        var gesture = KeyGesture()
        _ = gesture.controlDown(at: 0, holdToTalk: true)
        XCTAssertEqual(gesture.holdElapsed(at: 0.49), [])
    }

    func testControlPlusKeyBeforeHalfASecondCancels() {
        var gesture = KeyGesture()
        _ = gesture.controlDown(at: 0, holdToTalk: true)
        gesture.otherInput(at: 0.2)
        XCTAssertEqual(gesture.holdElapsed(at: 0.5), [])
        XCTAssertEqual(gesture.controlUp(at: 1), [])
    }

    func testControlPlusClickBeforeHalfASecondCancels() {
        var gesture = KeyGesture()
        _ = gesture.controlDown(at: 0, holdToTalk: true)
        gesture.otherInput(at: 0.4)
        XCTAssertEqual(gesture.holdElapsed(at: 0.5), [])
        XCTAssertEqual(gesture.controlUp(at: 0.6), [])
    }

    func testKeyWhileControlDownAlsoSpoilsAQuickTap() {
        var gesture = KeyGesture()
        _ = gesture.controlDown(at: 0, holdToTalk: true)
        gesture.otherInput(at: 0.05)
        XCTAssertEqual(gesture.controlUp(at: 0.1), [])
        _ = gesture.controlDown(at: 0.2, holdToTalk: true)
        XCTAssertEqual(gesture.controlUp(at: 0.3), [])
    }

    func testControlDownAgainAfterCancelDoesNotStartAHold() {
        var gesture = KeyGesture()
        _ = gesture.controlDown(at: 0, holdToTalk: true)
        gesture.otherInput(at: 0.1)
        _ = gesture.controlDown(at: 0.2, holdToTalk: true)
        XCTAssertEqual(gesture.holdElapsed(at: 0.8), [])
    }

    func testTypingAfterHoldStartDoesNotEndIt() {
        var gesture = KeyGesture()
        _ = gesture.controlDown(at: 0, holdToTalk: true)
        XCTAssertEqual(gesture.holdElapsed(at: 0.5), [.holdStart])
        gesture.otherInput(at: 1)
        gesture.otherInput(at: 1.5)
        XCTAssertTrue(gesture.isHolding)
        XCTAssertEqual(gesture.controlUp(at: 3), [.holdEnd])
    }

    func testReleaseAfterShortHoldThatWasNotATapDoesNothing() {
        var gesture = KeyGesture()
        _ = gesture.controlDown(at: 0, holdToTalk: true)
        XCTAssertEqual(gesture.controlUp(at: 0.4), [])
        _ = gesture.controlDown(at: 0.5, holdToTalk: true)
        XCTAssertEqual(gesture.controlUp(at: 0.6), [])
    }

    func testHoldEndOnlyAfterHoldStart() {
        var gesture = KeyGesture()
        _ = gesture.controlDown(at: 0, holdToTalk: true)
        XCTAssertEqual(gesture.controlUp(at: 0.45), [])
        _ = gesture.controlDown(at: 1, holdToTalk: true)
        XCTAssertEqual(gesture.holdElapsed(at: 1.5), [.holdStart])
        XCTAssertEqual(gesture.controlUp(at: 2), [.holdEnd])
        XCTAssertEqual(gesture.controlUp(at: 2.1), [])
    }

    func testHoldCancelsAnyPendingFirstTap() {
        var gesture = KeyGesture()
        _ = gesture.controlDown(at: 0, holdToTalk: true)
        _ = gesture.controlUp(at: 0.1)
        _ = gesture.controlDown(at: 0.2, holdToTalk: true)
        XCTAssertEqual(gesture.holdElapsed(at: 0.75), [.holdStart])
        XCTAssertEqual(gesture.controlUp(at: 0.9), [.holdEnd])
        _ = gesture.controlDown(at: 1.0, holdToTalk: true)
        XCTAssertEqual(gesture.controlUp(at: 1.1), [])
    }

    func testEscapeEndsAHoldWithoutHoldEnd() {
        var gesture = KeyGesture()
        _ = gesture.controlDown(at: 0, holdToTalk: true)
        XCTAssertEqual(gesture.holdElapsed(at: 0.5), [.holdStart])
        gesture.escape()
        XCTAssertFalse(gesture.isHolding)
        XCTAssertEqual(gesture.controlUp(at: 2), [])
    }

    func testTypingWithControlUpDoesNotBlockTheNextDoubleTap() {
        for holdToTalk in [false, true] {
            var gesture = KeyGesture()
            gesture.otherInput(at: 0)
            _ = gesture.controlDown(at: 1, holdToTalk: holdToTalk)
            XCTAssertEqual(gesture.controlUp(at: 1.1), [])
            _ = gesture.controlDown(at: 1.2, holdToTalk: holdToTalk)
            XCTAssertEqual(gesture.controlUp(at: 1.3), [.toggle])
        }
    }

    func testEscapeWithControlUpDoesNotBlockTheNextDoubleTap() {
        for holdToTalk in [false, true] {
            var gesture = KeyGesture()
            gesture.escape()
            _ = gesture.controlDown(at: 1, holdToTalk: holdToTalk)
            XCTAssertEqual(gesture.controlUp(at: 1.1), [])
            _ = gesture.controlDown(at: 1.2, holdToTalk: holdToTalk)
            XCTAssertEqual(gesture.controlUp(at: 1.3), [.toggle])
        }
    }

    func testControlPlusCNeverTogglesOrHolds() {
        var gesture = KeyGesture()
        _ = gesture.controlDown(at: 0, holdToTalk: true)
        gesture.otherInput(at: 0.1)
        XCTAssertEqual(gesture.controlUp(at: 0.2), [])
        _ = gesture.controlDown(at: 0.3, holdToTalk: true)
        gesture.otherInput(at: 0.35)
        XCTAssertEqual(gesture.holdElapsed(at: 0.9), [])
        XCTAssertEqual(gesture.controlUp(at: 1.0), [])
    }

    func testHoldToTalkDefaultsOff() {
        let key = "holdToTalk"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertFalse(Prefs.holdToTalk)
        UserDefaults.standard.set(true, forKey: key)
        XCTAssertTrue(Prefs.holdToTalk)
    }
}
