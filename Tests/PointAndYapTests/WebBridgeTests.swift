import XCTest
@testable import PointAndYap

final class WebBridgeTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "WebBridgeTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func item(_ id: String, title: String = "Fix it", status: String = "open") -> Item {
        Item(id: id, session: "s", n: 1, title: title, body: "body", crops: [], status: status, at: nil)
    }

    private func bridge(_ items: [Item] = []) -> WebBridge {
        WebBridge(defaults: defaults, loadItems: { items })
    }

    /// The JSON part of `window.pointroo.reply(<id>, <json>)`, read back as an object.
    private func replyObject(_ script: String) throws -> [String: Any] {
        let prefix = "window.pointroo.reply("
        XCTAssertTrue(script.hasPrefix(prefix))
        let inner = String(script.dropFirst(prefix.count).dropLast())
        let split = try XCTUnwrap(inner.range(of: ", {"))
        let json = "{" + inner[split.upperBound...]
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private func errorCode(_ script: String) throws -> String? {
        ((try replyObject(script))["error"] as? [String: Any])?["code"] as? String
    }

    func testReturnsAResultForAWhitelistedMethod() throws {
        let script = bridge([item("a#1"), item("b#1", status: "done")]).handle(message: ["id": 7, "method": "items.list", "params": ["status": "open"]])
        XCTAssertTrue(script.hasPrefix("window.pointroo.reply(7, "))
        let result = try XCTUnwrap(replyObject(script)["result"] as? [String: Any])
        let items = try XCTUnwrap(result["items"] as? [[String: Any]])
        XCTAssertEqual(items.map { $0["id"] as? String }, ["a#1"])
    }

    func testAcceptsAJsonStringAndGetsOneItem() throws {
        let script = bridge([item("a#1")]).handle(message: #"{"id":"x1","method":"items.get","params":{"id":"a#1"}}"#)
        XCTAssertTrue(script.hasPrefix(#"window.pointroo.reply("x1", "#))
        let result = try XCTUnwrap(replyObject(script)["result"] as? [String: Any])
        XCTAssertEqual((result["item"] as? [String: Any])?["title"] as? String, "Fix it")
        XCTAssertEqual(try errorCode(bridge().handle(message: ["id": 1, "method": "items.get", "params": ["id": "nope"]])), "not_found")
    }

    func testSendsTheFullItemFields() {
        var full = item("a#1")
        full.priority = "urgent"
        full.commit = "abc123"
        full.branch = "fix-it"
        full.duplicateOf = "a#0"
        full.alsoSaid = ["a#2: same again"]
        full.firstElement = "button|Save"
        full.said = "fix the save button"
        full.duration = 4.5
        let out = WebBridge.dictionary(full)
        XCTAssertEqual(out["priority"] as? String, "urgent")
        XCTAssertEqual(out["commit"] as? String, "abc123")
        XCTAssertEqual(out["branch"] as? String, "fix-it")
        XCTAssertEqual(out["duplicateOf"] as? String, "a#0")
        XCTAssertEqual(out["alsoSaid"] as? [String], ["a#2: same again"])
        XCTAssertEqual(out["firstElement"] as? String, "button|Save")
        XCTAssertEqual(out["said"] as? String, "fix the save button")
        XCTAssertEqual(out["duration"] as? Double, 4.5)
    }

    func testLeavesOutKeysThatHaveNoValue() {
        let out = WebBridge.dictionary(item("a#1"))
        for key in ["priority", "commit", "branch", "duplicateOf", "firstElement", "said", "duration", "project", "routeHow"] {
            XCTAssertNil(out[key], key)
        }
        XCTAssertEqual(out["alsoSaid"] as? [String], [])
    }

    func testKeepsTheOldItemKeys() {
        let out = WebBridge.dictionary(item("a#1", title: "T", status: "done"))
        XCTAssertEqual(out["id"] as? String, "a#1")
        XCTAssertEqual(out["session"] as? String, "s")
        XCTAssertEqual(out["n"] as? Int, 1)
        XCTAssertEqual(out["title"] as? String, "T")
        XCTAssertEqual(out["body"] as? String, "body")
        XCTAssertEqual(out["crops"] as? [String], [])
        XCTAssertEqual(out["status"] as? String, "done")
    }

    func testErrorsOnAnUnknownMethod() throws {
        XCTAssertEqual(try errorCode(bridge().handle(message: ["id": 1, "method": "files.delete"])), "unknown_method")
    }

    func testErrorsOnABadRequest() throws {
        XCTAssertEqual(try errorCode(bridge().handle(message: "not json")), "bad_request")
        XCTAssertEqual(try errorCode(bridge().handle(message: ["method": "items.list"])), "bad_request")
    }

    func testRerouteSaysNotAvailableYet() throws {
        let script = bridge().handle(message: ["id": 2, "method": "items.reroute", "params": ["id": "a#1", "project": "/x"]])
        XCTAssertEqual(try errorCode(script), "not_available")
        XCTAssertTrue(script.contains("not available yet"))
    }

    func testReadsAndWritesAllowedSettings() throws {
        let subject = bridge()
        let written = try replyObject(subject.handle(message: ["id": 1, "method": "settings.set", "params": ["key": "sounds", "value": false]]))
        XCTAssertEqual((written["result"] as? [String: Any])?["value"] as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "sounds") as? Bool, false)
        let read = try replyObject(subject.handle(message: ["id": 2, "method": "settings.get", "params": ["key": "sounds"]]))
        XCTAssertEqual((read["result"] as? [String: Any])?["value"] as? Bool, false)
    }

    func testRefusesASettingsKeyThatIsNotAllowed() throws {
        let subject = bridge()
        XCTAssertEqual(try errorCode(subject.handle(message: ["id": 1, "method": "settings.set", "params": ["key": "mcpPort", "value": 1]])), "refused")
        XCTAssertEqual(try errorCode(subject.handle(message: ["id": 2, "method": "settings.get", "params": ["key": "webDevURL"]])), "refused")
        XCTAssertNil(defaults.object(forKey: "mcpPort"))
    }

    func testRefusesAValueOfTheWrongKind() throws {
        let script = bridge().handle(message: ["id": 1, "method": "settings.set", "params": ["key": "sounds", "value": "yes"]])
        XCTAssertEqual(try errorCode(script), "bad_params")
        XCTAssertNil(defaults.object(forKey: "sounds"))
    }

    func testEscapesQuotesScriptTagsAndLineSeparators() throws {
        let nasty = "say \"hi\" </script><b>\u{2028}\u{2029}\\ end"
        let script = bridge([item("a#1", title: nasty)]).handle(message: ["id": 1, "method": "items.list"])
        XCTAssertFalse(script.contains("</script>"))
        XCTAssertFalse(script.contains("<"))
        XCTAssertFalse(script.contains("\u{2028}"))
        XCTAssertFalse(script.contains("\u{2029}"))
        let result = try XCTUnwrap(replyObject(script)["result"] as? [String: Any])
        let items = try XCTUnwrap(result["items"] as? [[String: Any]])
        XCTAssertEqual(items.first?["title"] as? String, nasty)
    }

    func testBuildsAnEmitScript() {
        XCTAssertEqual(WebBridge.emitScript(name: "items.changed", data: ["count": 2]), #"window.pointroo.emit("items.changed", {"count":2})"#)
    }

    func testAllowsOnlyBundleFilesAndTheDevOrigin() throws {
        let folder = URL(fileURLWithPath: "/Applications/Pointroo.app/Contents/Resources/ui", isDirectory: true)
        let dev = try XCTUnwrap(WebHost.devURL(from: "http://localhost:5173"))
        func allowed(_ text: String) -> Bool {
            WebHost.allows(URL(string: text)!, bundleFolder: folder, devOrigin: dev)
        }
        XCTAssertTrue(allowed("file:///Applications/Pointroo.app/Contents/Resources/ui/index.html"))
        XCTAssertTrue(allowed("file:///Applications/Pointroo.app/Contents/Resources/ui/assets/app.js"))
        XCTAssertFalse(allowed("file:///Applications/Pointroo.app/Contents/Resources/ui/../secret.txt"))
        XCTAssertFalse(allowed("file:///Applications/Pointroo.app/Contents/Resources/uix/index.html"))
        XCTAssertFalse(allowed("file:///etc/passwd"))
        XCTAssertTrue(allowed("http://localhost:5173/src/main.ts"))
        XCTAssertFalse(allowed("http://localhost:5174/"))
        XCTAssertFalse(allowed("https://localhost:5173/"))
        XCTAssertFalse(allowed("https://example.com/"))
        XCTAssertFalse(WebHost.allows(URL(string: "http://localhost:5173/")!, bundleFolder: folder, devOrigin: nil))
    }

    func testAcceptsOnlyLocalhostDevAddresses() {
        XCTAssertNotNil(WebHost.devURL(from: "http://localhost:5173"))
        XCTAssertNotNil(WebHost.devURL(from: "http://127.0.0.1:3000"))
        XCTAssertNil(WebHost.devURL(from: "http://example.com:5173"))
        XCTAssertNil(WebHost.devURL(from: "https://localhost:5173"))
        XCTAssertNil(WebHost.devURL(from: "http://localhost"))
        XCTAssertNil(WebHost.devURL(from: ""))
        XCTAssertNil(WebHost.devURL(from: nil))
    }
}
