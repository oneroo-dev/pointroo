import XCTest
@testable import PointAndYap

/// The follow-up picker after a recording with no route: when it opens and what it offers.
@MainActor
final class PickerChoicesTests: XCTestCase {
    private let backend = Project(name: "backend", path: "/work/backend")
    private let web = Project(name: "web", path: "/work/web")
    private let docs = Project(name: "docs", path: "/work/docs")

    private func listening(_ path: String, pid: Int32) -> LiveSession {
        LiveSession(pid: pid, cwd: path, agent: "claude", started: Date(timeIntervalSince1970: 1_800_000_000),
                    lastSeen: Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testNoSessionListeningOffersEveryKnownProject() {
        let choices = AppState.pickerChoices(known: [backend, web, docs], live: [])
        XCTAssertEqual(choices.map(\.name), ["backend", "web", "docs"])
    }

    func testOneListeningFolderOpensNoPicker() {
        let choices = AppState.pickerChoices(known: [backend, web, docs], live: [listening("/work/web", pid: 1)])
        XCTAssertTrue(choices.isEmpty)
    }

    func testTwoSessionsInOneFolderCountAsOneListeningFolder() {
        let live = [listening("/work/web", pid: 1), listening("/work/web/", pid: 2)]
        XCTAssertTrue(AppState.pickerChoices(known: [backend, web], live: live).isEmpty)
    }

    func testTwoListeningFoldersOfferListeningOnesFirst() {
        let live = [listening("/work/docs", pid: 1), listening("/work/web", pid: 2)]
        let choices = AppState.pickerChoices(known: [backend, web, docs], live: live)
        XCTAssertEqual(choices.map(\.name), ["web", "docs", "backend"])
    }

    func testNothingKnownOpensNoPicker() {
        XCTAssertTrue(AppState.pickerChoices(known: [], live: []).isEmpty)
    }
}
