import XCTest
@testable import PointAndYap

/// R27: the queue search (ItemSearch) and the bridge method items.search.
final class ItemSearchTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override class func setUp() { _ = PointAndYapTests.root }

    override func setUp() {
        suiteName = "ItemSearchTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func item(_ id: String, title: String = "Nothing", body: String = "", said: String = "", status: String = "open",
                      at: Date? = nil, note: String? = nil, project: String? = nil, alsoSaid: [String] = [],
                      firstElement: String? = nil) -> Item {
        Item(id: id, session: "s", n: 1, title: title, body: body, crops: [], status: status, at: at, note: note, project: project,
             alsoSaid: alsoSaid, said: said, firstElement: firstElement)
    }

    private func names(_ matches: [ItemSearch.Match]) -> [String] { matches.map(\.item.id) }

    private func search(_ items: [Item], _ text: String) -> [ItemSearch.Match] {
        ItemSearch.matches(items, text: text, projectName: { URL(fileURLWithPath: $0).lastPathComponent })
    }

    private func bridge(_ items: [Item]) -> WebBridge {
        WebBridge(defaults: defaults, loadItems: { items },
                  findProject: { _ in nil }, reroute: { _, _ in .moved }, loadProjects: { [] }, loadLive: { [] },
                  loadStatus: { AppStatus(mcpRunning: false, mcpPort: 1, mcpText: "", sessions: 0, agents: [],
                                          microphone: false, screenRecording: false, accessibility: false) },
                  changeStatus: { _, _, _ in .changed }, unroute: { _ in .unrouted }, writeClipboard: { _ in })
    }

    private func reply(_ subject: WebBridge, _ params: [String: Any]) throws -> [String: Any] {
        let object = try T1Support.replyObject(subject.handle(message: ["id": 1, "method": "items.search", "params": params]))
        return try XCTUnwrap(object["result"] as? [String: Any], "\(object)")
    }

    private func code(_ subject: WebBridge, _ params: [String: Any]) throws -> String? {
        try T1Support.errorCode(subject.handle(message: ["id": 1, "method": "items.search", "params": params]))
    }

    func testOneWordFindsTheItemsThatHoldIt() {
        let items = [item("a#1", title: "Fix the button"), item("a#2", title: "Other", said: "the colour is wrong"), item("a#3", title: "Nope")]
        XCTAssertEqual(names(search(items, "button")), ["a#1"])
        XCTAssertEqual(names(search(items, "colour")), ["a#2"])
        XCTAssertEqual(search(items, "missing").count, 0)
    }

    func testEveryWordMustMatchButNotInTheSameField() {
        let items = [item("a#1", title: "Fix the button", said: "make it blue"), item("a#2", title: "Fix the button"),
                     item("a#3", title: "Other", note: "button", project: "/work/backend")]
        XCTAssertEqual(names(search(items, "button blue")), ["a#1"])
        XCTAssertEqual(names(search(items, "button backend")), ["a#3"])
        XCTAssertEqual(search(items, "button purple").count, 0)
    }

    func testCaseAndAccentsAreIgnored() {
        let items = [item("a#1", title: "Caf\u{E9} menu"), item("a#2", title: "Resume")]
        XCTAssertEqual(names(search(items, "CAFE")), ["a#1"])
        XCTAssertEqual(names(search(items, "r\u{E9}sum\u{E9}")), ["a#2"])
        XCTAssertEqual(names(search(items, "caf\u{E9}")), ["a#1"])
    }

    func testEveryFieldCanMatchAndNamesTheField() {
        let items = [item("a#1", body: "alpha"), item("a#2", alsoSaid: ["a#9: beta"]), item("a#3", note: "gamma"),
                     item("a#4", project: "/work/delta"), item("a#5", firstElement: "AXButton|epsilon"), item("a#6", said: "zeta")]
        let fields = ["alpha": "body", "beta": "alsoSaid", "gamma": "note", "delta": "project", "epsilon": "firstElement", "zeta": "said"]
        for (word, field) in fields {
            let found = search(items, word)
            XCTAssertEqual(found.count, 1, word)
            XCTAssertEqual(found.first?.field, field, word)
        }
    }

    func testRankingTitleThenSaidAndBodyThenTheRestNewestFirst() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        let items = [
            item("rest-old", at: old, note: "login"),
            item("said-old", said: "login", at: old),
            item("title-old", title: "login", at: old),
            item("body-new", body: "login", at: new),
            item("title-new", title: "login", at: new),
            item("rest-new", at: new, note: "login"),
            item("title-none", title: "login"),
        ]
        XCTAssertEqual(names(search(items, "login")),
                       ["title-new", "title-old", "title-none", "body-new", "said-old", "rest-new", "rest-old"])
    }

    func testSnippetIsShortOnOneLineAndAroundTheHit() throws {
        let long = String(repeating: "x", count: 150) + "\nneedle here\n" + String(repeating: "y", count: 150)
        let found = try XCTUnwrap(search([item("a#1", said: long)], "needle").first)
        XCTAssertLessThanOrEqual(found.snippet.count, ItemSearch.snippetLength)
        XCTAssertFalse(found.snippet.contains("\n"))
        XCTAssertTrue(found.snippet.contains("needle"))
        let short = try XCTUnwrap(search([item("a#2", title: "line one\nline two")], "two").first)
        XCTAssertEqual(short.snippet, "line one line two")
    }

    func testBridgeStatusFilterAndTheMatchField() throws {
        let items = [item("a#1", title: "login", status: "open"), item("a#2", title: "login", status: "done"),
                     item("a#3", title: "login", status: "trashed")]
        let subject = bridge(items)
        let ids: ([String: Any]) throws -> [String] = { params in
            let found = try XCTUnwrap(try self.reply(subject, params)["items"] as? [[String: Any]])
            return found.compactMap { $0["id"] as? String }
        }
        XCTAssertEqual(Set(try ids(["text": "login"])), ["a#1", "a#2"])
        XCTAssertEqual(try ids(["text": "login", "status": "trashed"]), ["a#3"])
        XCTAssertEqual(try ids(["text": "login", "status": "done"]), ["a#2"])
        XCTAssertEqual(Set(try ids(["text": "login", "status": "any"])), ["a#1", "a#2", "a#3"])
        let first = try XCTUnwrap(try reply(subject, ["text": "login"])["items"] as? [[String: Any]]).first
        let match = try XCTUnwrap(first?["match"] as? [String: Any])
        XCTAssertEqual(match["field"] as? String, "title")
        XCTAssertEqual(match["snippet"] as? String, "login")
    }

    func testBridgeLimit() throws {
        let items = (1...5).map { item("a#\($0)", title: "login") }
        let subject = bridge(items)
        XCTAssertEqual(try XCTUnwrap(try reply(subject, ["text": "login", "limit": 2])["items"] as? [[String: Any]]).count, 2)
        XCTAssertEqual(try XCTUnwrap(try reply(subject, ["text": "login"])["items"] as? [[String: Any]]).count, 5)
    }

    func testBridgeBadParams() throws {
        let subject = bridge([item("a#1", title: "login")])
        let tooLong = String(repeating: "a", count: 201)
        let bad: [[String: Any]] = [
            [:], ["text": ""], ["text": "   "], ["text": 5], ["text": true], ["text": tooLong],
            ["text": "login", "limit": true], ["text": "login", "limit": 0], ["text": "login", "limit": 101],
            ["text": "login", "limit": 1.5], ["text": "login", "limit": "3"],
            ["text": "login", "status": "bogus"], ["text": "login", "status": 5],
        ]
        for params in bad {
            XCTAssertEqual(try code(subject, params), "bad_params", "\(params)")
        }
        XCTAssertNil(try code(subject, ["text": String(repeating: "a", count: 200)]))
    }
}
