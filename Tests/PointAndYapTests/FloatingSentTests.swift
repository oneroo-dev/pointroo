import XCTest
@testable import PointAndYap

/// route.sent (an automatic send, once per recording) and the arrival of a new agent question: the two decisions behind the kit
/// pill's "Sent to X / Undo" and the question card.
final class FloatingSentTests: XCTestCase {
    private func item(session: String, n: Int = 1, how: String? = "said", project: String? = "/work/app", status: String = "open",
                      practice: Bool = false) -> Item {
        var made = Item(id: "\(session)#\(n)", session: session, n: n, title: "Fix it", body: "body", crops: [], status: status, at: nil)
        made.routeHow = how
        made.project = project
        made.practice = practice
        return made
    }

    private func name(_ path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }

    func testTheFirstReadSendsNothingEvenForRoutedSessions() {
        var events = WebEvents()
        XCTAssertTrue(events.routeSent([item(session: "old")], projectName: name).isEmpty)
    }

    func testANewAutoRoutedSessionFiresOnceWithItsDetails() throws {
        var events = WebEvents()
        _ = events.routeSent([item(session: "old")], projectName: name)
        let items = [item(session: "old"), item(session: "new", n: 2, how: "screen"), item(session: "new", n: 1, how: "screen")]
        let result = events.routeSent(items, projectName: name)
        XCTAssertEqual(result.map(\.name), ["route.sent"])
        let data = try XCTUnwrap(result.first?.data)
        XCTAssertEqual(data["session"] as? String, "new")
        XCTAssertEqual(data["project"] as? String, "/work/app")
        XCTAssertEqual(data["projectName"] as? String, "app")
        XCTAssertEqual(data["how"] as? String, "screen")
        XCTAssertEqual(data["ids"] as? [String], ["new#1", "new#2"])
        XCTAssertTrue(events.routeSent(items, projectName: name).isEmpty)
    }

    func testEveryAutomaticHowFires() {
        var events = WebEvents()
        _ = events.routeSent([], projectName: name)
        let items = ["said", "screen", "followup", "only"].map { item(session: "s-\($0)", how: $0) }
        XCTAssertEqual(events.routeSent(items, projectName: name).count, 4)
    }

    func testAPickedSessionNeverFires() {
        var events = WebEvents()
        _ = events.routeSent([], projectName: name)
        XCTAssertTrue(events.routeSent([item(session: "p", how: "picked")], projectName: name).isEmpty)
        XCTAssertTrue(events.routeSent([item(session: "p", how: "picked")], projectName: name).isEmpty)
    }

    func testASessionWithoutARouteFiresWhenTheRouteAppears() {
        var events = WebEvents()
        _ = events.routeSent([item(session: "s", how: nil, project: nil)], projectName: name)
        XCTAssertTrue(events.routeSent([item(session: "s", how: nil, project: nil)], projectName: name).isEmpty)
        XCTAssertEqual(events.routeSent([item(session: "s")], projectName: name).count, 1)
    }

    func testPracticeAndTrashedItemsAreLeftOut() {
        var events = WebEvents()
        _ = events.routeSent([], projectName: name)
        let items = [item(session: "practice", practice: true), item(session: "gone", status: "trashed")]
        XCTAssertTrue(events.routeSent(items, projectName: name).isEmpty)
    }

    func testProjectNameIsAskedOnlyForASessionThatFires() {
        var events = WebEvents()
        var asked: [String] = []
        _ = events.routeSent([item(session: "old", project: "/work/old")], projectName: { asked.append($0); return $0 })
        XCTAssertTrue(asked.isEmpty)
        _ = events.routeSent([item(session: "old", project: "/work/old"), item(session: "new", project: "/work/new")],
                             projectName: { asked.append($0); return $0 })
        XCTAssertEqual(asked, ["/work/new"])
    }

    func testTheFirstQuestionLookOnlyLearnsTheSet() {
        var arrivals = QuestionArrivals()
        XCTAssertTrue(arrivals.arrived(["a", "b"]).isEmpty)
        XCTAssertTrue(arrivals.arrived(["a", "b"]).isEmpty)
    }

    func testANewQuestionIdArrivesOnce() {
        var arrivals = QuestionArrivals()
        _ = arrivals.arrived(["a"])
        XCTAssertEqual(arrivals.arrived(["a", "b"]), ["b"])
        XCTAssertTrue(arrivals.arrived(["a", "b"]).isEmpty)
    }

    func testAnAnsweredOrSnoozedQuestionDoesNotArrive() {
        var arrivals = QuestionArrivals()
        _ = arrivals.arrived(["a", "b"])
        XCTAssertTrue(arrivals.arrived(["b"]).isEmpty)
        XCTAssertTrue(arrivals.arrived([]).isEmpty)
    }

    func testASnoozedQuestionArrivesAgainWhenItComesBack() {
        var arrivals = QuestionArrivals()
        _ = arrivals.arrived(["a"])
        _ = arrivals.arrived([])
        XCTAssertEqual(arrivals.arrived(["a"]), ["a"])
    }
}
