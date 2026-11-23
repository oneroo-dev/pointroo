import XCTest
@testable import PointAndYap

final class ListenWindowTests: XCTestCase {
    private let good = ListenWindow.Conditions(settingOn: true, phaseIdle: true, micBusyElsewhere: false,
                                               idleSeconds: 5, screenLocked: false)
    private let loud: Float = 0.5
    private let quiet: Float = 0.001

    /// A window that is open at time 0.
    private func opened() -> ListenWindow {
        var window = ListenWindow()
        XCTAssertEqual(window.bannerShown(at: 0, conditions: good), [.start])
        return window
    }

    /// Speech from `from` for a quarter of a second, in steps that are exact in binary.
    private func speak(_ window: inout ListenWindow, from: Double) {
        for step in 0...4 { window.level(loud, at: from + Double(step) * 0.0625) }
    }

    func testSettingOffNeverStarts() {
        var window = ListenWindow()
        var conditions = good
        conditions.settingOn = false
        XCTAssertEqual(window.bannerShown(at: 0, conditions: conditions), [])
        XCTAssertFalse(window.isListening)
    }

    func testBannerStartsARecording() {
        var window = ListenWindow()
        XCTAssertEqual(window.bannerShown(at: 0, conditions: good), [.start])
        XCTAssertTrue(window.isListening)
    }

    func testSilentCancelAfterSixSecondsWithNoSpeech() {
        var window = opened()
        XCTAssertEqual(window.tick(at: 5.5), [])
        XCTAssertEqual(window.tick(at: 6), [.cancelSilently])
        XCTAssertFalse(window.isListening)
    }

    func testAShortBlipIsNotSpeech() {
        var window = opened()
        window.level(loud, at: 1)
        window.level(quiet, at: 1.0625)
        XCTAssertEqual(window.tick(at: 6), [.cancelSilently])
    }

    func testStopsAfterOnePointTwoSecondsOfSilenceAfterSpeech() {
        var window = opened()
        speak(&window, from: 1)
        // The last loud sample is at 1.25.
        XCTAssertEqual(window.tick(at: 2.25), [])
        XCTAssertEqual(window.tick(at: 2.5), [.stop])
        XCTAssertFalse(window.isListening)
    }

    func testSpeechAfterTheSixSecondMarkIsNotNeededWhenSpeechCameEarly() {
        var window = opened()
        speak(&window, from: 5)
        XCTAssertEqual(window.tick(at: 6.25), [])
    }

    func testStopsAtTwentySecondsEvenWhileTalking() {
        var window = opened()
        var time = 1.0
        while time < 20 {
            window.level(loud, at: time)
            XCTAssertEqual(window.tick(at: time), [])
            time += 0.0625
        }
        window.level(loud, at: 20)
        XCTAssertEqual(window.tick(at: 20), [.stop])
    }

    func testMicBusyElsewhereNeverStarts() {
        var window = ListenWindow()
        var conditions = good
        conditions.micBusyElsewhere = true
        XCTAssertEqual(window.bannerShown(at: 0, conditions: conditions), [])
    }

    func testIdleForMoreThanTwoMinutesNeverStarts() {
        var window = ListenWindow()
        var conditions = good
        conditions.idleSeconds = 120.5
        XCTAssertEqual(window.bannerShown(at: 0, conditions: conditions), [])
    }

    func testIdleForExactlyTwoMinutesStillStarts() {
        var window = ListenWindow()
        var conditions = good
        conditions.idleSeconds = 120
        XCTAssertEqual(window.bannerShown(at: 0, conditions: conditions), [.start])
    }

    func testLockedScreenNeverStarts() {
        var window = ListenWindow()
        var conditions = good
        conditions.screenLocked = true
        XCTAssertEqual(window.bannerShown(at: 0, conditions: conditions), [])
    }

    func testNotIdlePhaseNeverStarts() {
        var window = ListenWindow()
        var conditions = good
        conditions.phaseIdle = false
        XCTAssertEqual(window.bannerShown(at: 0, conditions: conditions), [])
    }

    func testOnlyTheFirstBannerInThirtySecondsOpensAWindow() {
        var window = opened()
        XCTAssertEqual(window.tick(at: 6), [.cancelSilently])
        XCTAssertEqual(window.bannerShown(at: 10, conditions: good), [])
        XCTAssertEqual(window.bannerShown(at: 29.5, conditions: good), [])
        XCTAssertEqual(window.bannerShown(at: 30, conditions: good), [.start])
    }

    func testABannerThatCouldNotOpenStillUsesUpTheThirtySeconds() {
        var window = ListenWindow()
        var busy = good
        busy.micBusyElsewhere = true
        XCTAssertEqual(window.bannerShown(at: 0, conditions: busy), [])
        XCTAssertEqual(window.bannerShown(at: 8, conditions: good), [])
    }

    func testEscapeClosesWithNothingKept() {
        var window = opened()
        speak(&window, from: 1)
        XCTAssertEqual(window.escape(), [.cancelSilently])
        XCTAssertFalse(window.isListening)
        XCTAssertEqual(window.tick(at: 30), [])
    }

    func testEscapeWhenNotListeningDoesNothing() {
        var window = ListenWindow()
        XCTAssertEqual(window.escape(), [])
    }

    func testUserTakingOverWithControlEndsTheWindowWithoutActions() {
        var window = opened()
        window.userTookOver()
        XCTAssertFalse(window.isListening)
        XCTAssertEqual(window.tick(at: 6), [])
        XCTAssertEqual(window.tick(at: 30), [])
    }
}
