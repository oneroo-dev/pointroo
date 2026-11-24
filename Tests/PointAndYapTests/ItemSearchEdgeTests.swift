import XCTest
@testable import PointAndYap

/// T2: edge cases of the queue search (ItemSearch and items.search): punctuation, emoji, the length limit, snippets, empty fields.
final class ItemSearchEdgeTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override class func setUp() { _ = PointAndYapTests.root }

    override func setUp() {
        suiteName = "ItemSearchEdgeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func item(_ id: String, title: String = "Nothing", body: String = "", said: String = "", note: String? = nil,
                      project: String? = nil, alsoSaid: [String] = [], firstElement: String? = nil) -> Item {
        Item(id: id, session: "s", n: 1, title: title, body: body, crops: [], status: "open", at: nil, note: note, project: project,
             alsoSaid: alsoSaid, said: said, firstElement: firstElement)
    }

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

    private func script(_ subject: WebBridge, _ text: String) -> String {
        subject.handle(message: ["id": 1, "method": "items.search", "params": ["text": text]])
    }

    private func foundIds(_ subject: WebBridge, _ text: String) throws -> [String] {
        let object = try T1Support.replyObject(script(subject, text))
        let result = try XCTUnwrap(object["result"] as? [String: Any], "\(object)")
        let found = try XCTUnwrap(result["items"] as? [[String: Any]])
        return found.compactMap { $0["id"] as? String }
    }

    func testPunctuationIsMatchedAsPlainText() {
        let items = [item("a#1", title: "It can't open (again) [now] *really* a+b?"), item("a#2", title: "plain words")]
        for word in ["can't", "(again)", "[now]", "*really*", "a+b?", ".*", "\\"] {
            let expected = word == ".*" || word == "\\" ? [] : ["a#1"]
            XCTAssertEqual(search(items, word).map(\.item.id), expected, word)
        }
    }

    func testQuotesInTextAndThroughTheBridge() throws {
        let items = [item("a#1", title: "Say \"hello\" to it"), item("a#2", said: "the 'button' is wrong"), item("a#3", title: "none")]
        XCTAssertEqual(search(items, "\"hello\"").map(\.item.id), ["a#1"])
        XCTAssertEqual(search(items, "'button'").map(\.item.id), ["a#2"])
        XCTAssertEqual(search(items, "\"").map(\.item.id), ["a#1"])
        let subject = bridge(items)
        XCTAssertEqual(try foundIds(subject, "\"hello\""), ["a#1"])
        XCTAssertEqual(try foundIds(subject, "'button' \"x"), [])
        XCTAssertEqual(try foundIds(subject, "\\\"hello"), [])
    }

    func testEmojiAreFoundAndKeptWhole() throws {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        let items = [item("a#1", title: "Party \u{1F389} time"), item("a#2", said: "family \(family) photo"), item("a#3", title: "no emoji")]
        XCTAssertEqual(search(items, "\u{1F389}").map(\.item.id), ["a#1"])
        XCTAssertEqual(search(items, family).map(\.item.id), ["a#2"])
        XCTAssertEqual(try XCTUnwrap(search(items, "\u{1F389}").first).snippet, "Party \u{1F389} time")
        let long = String(repeating: family, count: 120) + " needle " + String(repeating: family, count: 120)
        let found = try XCTUnwrap(search([item("a#4", said: long)], "needle").first)
        XCTAssertLessThanOrEqual(found.snippet.count, ItemSearch.snippetLength)
        XCTAssertTrue(found.snippet.contains("needle"))
        XCTAssertEqual(try foundIds(bridge(items), "\u{1F389}"), ["a#1"])
    }

    func testTwoHundredCharactersAreAcceptedAndTwoHundredAndOneAreNotEvenWithEmoji() throws {
        let subject = bridge([item("a#1", title: "x")])
        let twoHundred = String(repeating: "\u{1F389}", count: 200)
        let reply = try T1Support.replyObject(script(subject, twoHundred))
        XCTAssertNotNil(reply["result"], "\(reply)")
        XCTAssertNil(reply["error"])
        XCTAssertEqual(try T1Support.errorCode(script(subject, twoHundred + "\u{1F389}")), "bad_params")
        let spaced = "a " + String(repeating: "b", count: 196) + " c"
        XCTAssertEqual(spaced.count, 200)
        XCTAssertNil(try T1Support.errorCode(script(subject, spaced)))
        XCTAssertEqual(try T1Support.errorCode(script(subject, spaced + "d")), "bad_params")
    }

    func testWordsInDifferentFieldsMatchTogetherAndTheSnippetComesFromTheBestField() throws {
        let items = [item("a#1", title: "Fix the login", said: "page is broken")]
        XCTAssertEqual(search(items, "login page").map(\.item.id), ["a#1"])
        XCTAssertEqual(search(items, "login page").first?.field, "title")
        XCTAssertEqual(search(items, "page login").map(\.item.id), ["a#1"])
        XCTAssertEqual(search(items, "login broken missing").count, 0)
        let joined = try XCTUnwrap(search(items, "login page").first)
        XCTAssertEqual(joined.snippet, "Fix the login")
    }

    func testWordsSplitAcrossProjectNoteAndAlsoSaid() {
        let items = [item("a#1", note: "needs review", project: "/work/backend", alsoSaid: ["a#9: also the footer"])]
        XCTAssertEqual(search(items, "review backend footer").count, 1)
        XCTAssertEqual(search(items, "review backend footers").count, 0)
        XCTAssertEqual(search(items, "/work").count, 0)
    }

    func testSnippetAtTheVeryStartOfAField() throws {
        let found = try XCTUnwrap(search([item("a#1", said: "needle" + String(repeating: "y", count: 200))], "needle").first)
        XCTAssertTrue(found.snippet.hasPrefix("needle"))
        XCTAssertEqual(found.snippet.count, ItemSearch.snippetLength)
    }

    func testSnippetAtTheVeryEndOfAField() throws {
        let found = try XCTUnwrap(search([item("a#1", said: String(repeating: "x", count: 200) + "needle")], "needle").first)
        XCTAssertTrue(found.snippet.hasSuffix("needle"))
        XCTAssertEqual(found.snippet.count, ItemSearch.snippetLength)
    }

    func testSnippetOfAShortFieldIsTheWholeField() throws {
        let found = try XCTUnwrap(search([item("a#1", said: "needle")], "needle").first)
        XCTAssertEqual(found.snippet, "needle")
        let exact = String(repeating: "a", count: 40) + "needle" + String(repeating: "b", count: 34)
        XCTAssertEqual(exact.count, ItemSearch.snippetLength)
        XCTAssertEqual(try XCTUnwrap(search([item("a#2", said: exact)], "needle").first).snippet, exact)
    }

    func testSnippetStartsTwentyCharactersBeforeAHitInTheMiddle() throws {
        let text = String(repeating: "a", count: 100) + "needle" + String(repeating: "b", count: 100)
        let found = try XCTUnwrap(search([item("a#1", said: text)], "needle").first)
        XCTAssertEqual(found.snippet, String(repeating: "a", count: 20) + "needle" + String(repeating: "b", count: 54))
    }

    func testAnItemWithEmptyFieldsMatchesNothingAndDoesNotCrash() {
        let empty = item("a#1", title: "", body: "", said: "", note: "", project: nil, alsoSaid: [], firstElement: "")
        XCTAssertEqual(search([empty], "x").count, 0)
        XCTAssertEqual(search([empty, item("a#2", title: "x")], "x").map(\.item.id), ["a#2"])
        let onlyNote = item("a#3", title: "", note: "late")
        let found = search([onlyNote], "late")
        XCTAssertEqual(found.first?.field, "note")
        XCTAssertEqual(found.first?.snippet, "late")
    }

    func testItemsWithEmptyAlsoSaidEntriesAndBlankLines() {
        let blank = item("a#1", title: "\n\n", said: "  \n ", alsoSaid: ["", ""])
        XCTAssertEqual(search([blank], "a").count, 0)
        let spread = item("a#2", title: "top\n\nbottom")
        XCTAssertEqual(search([spread], "bottom").first?.snippet, "top  bottom")
    }

    func testNoItemsAndWhitespaceOnlyTextGiveNothing() {
        XCTAssertEqual(search([], "x").count, 0)
        XCTAssertEqual(search([item("a#1")], "   \n\t ").count, 0)
        XCTAssertEqual(search([item("a#1")], "").count, 0)
    }
}
