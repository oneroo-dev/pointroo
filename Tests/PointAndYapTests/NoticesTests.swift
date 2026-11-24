import XCTest
@testable import PointAndYap

final class NoticesTests: XCTestCase {
    private var folder: URL!
    private var suiteName = ""
    private var defaults: UserDefaults!

    override class func setUp() { _ = PointAndYapTests.root }

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("notices-\(UUID().uuidString)")
        suiteName = "NoticesTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func item(_ id: String, status: String = "done", by: String? = "claude", at: TimeInterval = 100) -> Item {
        var made = Item(id: id, session: "s", n: 1, title: "Fix it", body: "body", crops: [], status: status,
                        at: Date(timeIntervalSince1970: at))
        made.by = by
        made.note = "fixed \(id)"
        return made
    }

    private func question(_ id: String, asked: TimeInterval) -> Question {
        Question(id: id, project: "backend", cwd: "/work/backend", agent: "claude", text: "Which?", choices: ["a", "b"],
                 asked: Date(timeIntervalSince1970: asked))
    }

    private func bridge(items: [Item] = [], questions: [Question] = []) -> WebBridge {
        WebBridge(defaults: defaults, loadItems: { items }, loadProjects: { [] }, loadLive: { [] },
                  now: { Date(timeIntervalSince1970: 1000) },
                  loadQuestions: { _ in questions },
                  noticeStore: NoticeStore(folder: folder))
    }

    private func result(_ subject: WebBridge, _ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        let reply = try T1Support.replyObject(subject.handle(message: ["id": 1, "method": method, "params": params]))
        return try XCTUnwrap(reply["result"] as? [String: Any], "\(reply)")
    }

    private func code(_ subject: WebBridge, _ method: String, _ params: [String: Any]) throws -> String? {
        try T1Support.errorCode(subject.handle(message: ["id": 1, "method": method, "params": params]))
    }

    private func notices(_ subject: WebBridge, _ params: [String: Any] = [:]) throws -> [[String: Any]] {
        try XCTUnwrap(result(subject, "notices.list", params)["notices"] as? [[String: Any]])
    }

    func testDoneItemNotSeenYetShows() throws {
        let list = try notices(bridge(items: [item("a#1")]))
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0]["kind"] as? String, "done")
        XCTAssertEqual(list[0]["id"] as? String, "a#1")
        XCTAssertEqual(list[0]["agent"] as? String, "claude")
        XCTAssertEqual(list[0]["note"] as? String, "fixed a#1")
        XCTAssertNotNil(list[0]["at"] as? String)
    }

    func testOpenAndInProgressItemsDoNotShow() throws {
        let list = try notices(bridge(items: [item("a#1", status: "open"), item("b#1", status: "in_progress")]))
        XCTAssertTrue(list.isEmpty)
    }

    func testSeenHidesTheNotice() throws {
        let subject = bridge(items: [item("a#1"), item("b#1")])
        XCTAssertEqual(try result(subject, "notices.seen", ["ids": ["a#1"]])["seen"] as? Int, 1)
        let list = try notices(subject)
        XCTAssertEqual(list.map { $0["id"] as? String }, ["b#1"])
    }

    func testSeenIsKeptOnDiskForANewBridge() throws {
        _ = try result(bridge(items: [item("a#1")]), "notices.seen", ["ids": ["a#1"]])
        XCTAssertTrue(try notices(bridge(items: [item("a#1")])).isEmpty)
    }

    func testYouAndUserNeverShow() throws {
        let list = try notices(bridge(items: [item("a#1", by: "you"), item("b#1", by: "user"), item("c#1", by: nil), item("d#1", by: "claude")]))
        XCTAssertEqual(list.map { $0["id"] as? String }, ["d#1"])
    }

    func testQuestionsAreMixedInNewestFirst() throws {
        let subject = bridge(items: [item("a#1", at: 100), item("b#1", at: 300)],
                             questions: [question("q1", asked: 200), question("q2", asked: 400)])
        let list = try notices(subject)
        XCTAssertEqual(list.map { $0["id"] as? String }, ["q2", "b#1", "q1", "a#1"])
        XCTAssertEqual(list.map { $0["kind"] as? String }, ["question", "done", "question", "done"])
        XCTAssertEqual(list[0]["text"] as? String, "Which?")
        XCTAssertEqual(list[0]["choices"] as? [String], ["a", "b"])
        XCTAssertEqual(list[0]["asked"] as? Double, 400)
    }

    func testSeenDoesNotHideQuestions() throws {
        let subject = bridge(questions: [question("q1", asked: 200)])
        XCTAssertEqual(try result(subject, "notices.seen", ["ids": ["q1"]])["seen"] as? Int, 0)
        XCTAssertEqual(try notices(subject).count, 1)
    }

    func testUnknownIdsAreIgnored() throws {
        let subject = bridge(items: [item("a#1")])
        XCTAssertEqual(try result(subject, "notices.seen", ["ids": ["nope", "a#1", "also-nope"]])["seen"] as? Int, 1)
        XCTAssertEqual(NoticeStore(folder: folder).seenIds(), ["a#1"])
    }

    func testLimitCutsTheListAndDefaultsToTwenty() throws {
        let many = (1...25).map { item("a#\($0)", at: TimeInterval($0)) }
        let subject = bridge(items: many)
        XCTAssertEqual(try notices(subject).count, 20)
        let three = try notices(subject, ["limit": 3])
        XCTAssertEqual(three.map { $0["id"] as? String }, ["a#25", "a#24", "a#23"])
    }

    func testSeenListKeepsOnlyTheNewestFiveHundred() {
        let store = NoticeStore(folder: folder)
        XCTAssertTrue(store.markSeen((1...450).map { "id\($0)" }))
        XCTAssertTrue(store.markSeen((451...520).map { "id\($0)" }))
        let seen = store.seenIds()
        XCTAssertEqual(seen.count, 500)
        XCTAssertEqual(seen.first, "id21")
        XCTAssertEqual(seen.last, "id520")
    }

    func testMarkingTheSameIdTwiceStoresItOnce() {
        let store = NoticeStore(folder: folder)
        store.markSeen(["a#1", "b#1"])
        store.markSeen(["a#1"])
        XCTAssertEqual(store.seenIds(), ["a#1", "b#1"])
    }

    func testBadParams() throws {
        let subject = bridge(items: [item("a#1")])
        for bad: Any in [0, 51, -1, 1.5, "5", true, NSNull(), [1]] {
            XCTAssertEqual(try code(subject, "notices.list", ["limit": bad]), "bad_params", "limit \(bad)")
        }
        XCTAssertEqual(try code(subject, "notices.seen", [:]), "bad_params")
        for bad: Any in ["a#1", 5, true, NSNull(), ["id": "a#1"], [1], ["a#1", 2]] {
            XCTAssertEqual(try code(subject, "notices.seen", ["ids": bad]), "bad_params", "ids \(bad)")
        }
    }

    func testNoticesChangedOnceForEachChange() {
        var events = WebEvents()
        let first = events.notices(["done:a#1", "question:q1"])
        XCTAssertEqual(first.map(\.name), ["notices.changed"])
        XCTAssertEqual(first[0].data["count"] as? Int, 2)
        XCTAssertTrue(events.notices(["question:q1", "done:a#1"]).isEmpty)
        XCTAssertEqual(events.notices(["done:a#1"]).count, 1)
        XCTAssertTrue(events.notices(["done:a#1"]).isEmpty)
    }

    func testFirstNoticesCallEmitsEvenWhenThereAreNone() {
        var events = WebEvents()
        XCTAssertEqual(events.notices([]).count, 1)
        XCTAssertTrue(events.notices([]).isEmpty)
    }

    func testIdentifiersFollowTheSeenSetAndSkipYou() {
        let ids = Notices.identifiers(items: [item("a#1"), item("b#1"), item("c#1", by: "you")],
                                      questions: [question("q1", asked: 1)], seen: ["a#1"])
        XCTAssertEqual(ids, ["done:b#1", "question:q1"])
    }
}
