import XCTest
@testable import PointAndYap

@MainActor
final class MainWindowChoiceTests: XCTestCase {
    func testDecisionTable() {
        XCTAssertEqual(MainWindowChoice.decide(kitWindow: true, uiAvailable: true), .kit)
        XCTAssertEqual(MainWindowChoice.decide(kitWindow: true, uiAvailable: false), .classic)
        XCTAssertEqual(MainWindowChoice.decide(kitWindow: false, uiAvailable: true), .classic)
        XCTAssertEqual(MainWindowChoice.decide(kitWindow: false, uiAvailable: false), .classic)
    }

    func testSwapsOncePerRealChange() {
        var wanted = MainWindowChoice.kit
        var swaps: [MainWindowChoice] = []
        let swapper = MainWindowSwapper(shown: .kit, wanted: { wanted }, swap: { swaps.append($0) })

        wanted = .classic
        XCTAssertTrue(swapper.settingsMayHaveChanged())
        XCTAssertFalse(swapper.settingsMayHaveChanged())
        XCTAssertEqual(swaps, [.classic])
        XCTAssertEqual(swapper.shown, .classic)

        wanted = .kit
        XCTAssertTrue(swapper.settingsMayHaveChanged())
        XCTAssertEqual(swaps, [.classic, .kit])
        XCTAssertEqual(swapper.shown, .kit)
    }

    func testNeverSwapsWhenUnchanged() {
        var swapCount = 0
        let swapper = MainWindowSwapper(shown: .classic, wanted: { .classic }, swap: { _ in swapCount += 1 })
        XCTAssertFalse(swapper.settingsMayHaveChanged())
        XCTAssertFalse(swapper.settingsMayHaveChanged())
        XCTAssertEqual(swapCount, 0)
    }

    func testChangeMadeDuringTheSwapDoesNotSwapAgain() {
        var swapCount = 0
        var swapperReference: MainWindowSwapper?
        let swapper = MainWindowSwapper(shown: .kit, wanted: { .classic }, swap: { _ in
            swapCount += 1
            swapperReference?.settingsMayHaveChanged()
        })
        swapperReference = swapper
        XCTAssertTrue(swapper.settingsMayHaveChanged())
        XCTAssertEqual(swapCount, 1)
    }
}
