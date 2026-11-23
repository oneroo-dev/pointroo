import XCTest
@testable import PointAndYap

final class WebBridgeTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override class func setUp() { _ = PointAndYapTests.root }

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

    private final class RerouteCalls {
        var calls: [(String, Project)] = []
    }

    func testRerouteCallsTheInjectedClosureWithTheProject() throws {
        let calls = RerouteCalls()
        let target = Project(name: "backend", path: "/work/backend")
        let subject = WebBridge(defaults: defaults, loadItems: { [] },
                                findProject: { $0 == "backend" ? target : nil },
                                reroute: { calls.calls.append(($0, $1)); return .moved })
        let reply = try replyObject(subject.handle(message: ["id": 2, "method": "items.reroute", "params": ["id": "a#1", "project": "backend"]]))
        XCTAssertEqual((reply["result"] as? [String: Any])?["moved"] as? Bool, true)
        XCTAssertEqual(calls.calls.count, 1)
        XCTAssertEqual(calls.calls.first?.0, "a#1")
        XCTAssertEqual(calls.calls.first?.1, target)
    }

    func testRerouteToAnUnknownProjectIsNotFound() throws {
        let calls = RerouteCalls()
        let subject = WebBridge(defaults: defaults, loadItems: { [] }, findProject: { _ in nil },
                                reroute: { calls.calls.append(($0, $1)); return .moved })
        let script = subject.handle(message: ["id": 2, "method": "items.reroute", "params": ["id": "a#1", "project": "nowhere"]])
        XCTAssertEqual(try errorCode(script), "not_found")
        XCTAssertTrue(calls.calls.isEmpty)
    }

    func testRerouteMapsTheOtherResults() throws {
        let target = Project(name: "backend", path: "/work/backend")
        func code(_ result: Items.RerouteResult) throws -> String? {
            let subject = WebBridge(defaults: defaults, loadItems: { [] }, findProject: { _ in target }, reroute: { _, _ in result })
            return try errorCode(subject.handle(message: ["id": 1, "method": "items.reroute", "params": ["id": "a#1", "project": "backend"]]))
        }
        XCTAssertEqual(try code(.missing), "not_found")
        XCTAssertEqual(try code(.done), "refused")
        XCTAssertEqual(try code(.saveFailed), "not_available")
        XCTAssertEqual(try errorCode(bridge().handle(message: ["id": 1, "method": "items.reroute", "params": ["id": "a#1"]])), "bad_params")
    }

    func testQuestionsListIsEmptyWhenNothingIsAsked() throws {
        try? FileManager.default.removeItem(at: Questions.folder)
        let result = try XCTUnwrap(replyObject(bridge().handle(message: ["id": 1, "method": "questions.list"]))["result"] as? [String: Any])
        XCTAssertEqual((result["questions"] as? [Any])?.count, 0)
    }

    func testQuestionsListShowsAnOpenQuestion() throws {
        try? FileManager.default.removeItem(at: Questions.folder)
        let question = Questions.ask(project: "alpha", cwd: "/w/alpha", agent: "claude", text: "Blue or gray?", choices: ["Blue", "Gray"])
        let result = try XCTUnwrap(replyObject(bridge().handle(message: ["id": 1, "method": "questions.list"]))["result"] as? [String: Any])
        let questions = try XCTUnwrap(result["questions"] as? [[String: Any]])
        XCTAssertEqual(questions.count, 1)
        XCTAssertEqual(questions.first?["id"] as? String, question.id)
        XCTAssertEqual(questions.first?["project"] as? String, "alpha")
        XCTAssertEqual(questions.first?["agent"] as? String, "claude")
        XCTAssertEqual(questions.first?["text"] as? String, "Blue or gray?")
        XCTAssertEqual(questions.first?["choices"] as? [String], ["Blue", "Gray"])
        XCTAssertNotNil(questions.first?["asked"] as? Double)
        XCTAssertNil(questions.first?["cwd"])
    }

    func testQuestionsAnswerStoresTheAnswerOnceOnly() throws {
        try? FileManager.default.removeItem(at: Questions.folder)
        let question = Questions.ask(project: "alpha", cwd: "/w/alpha", agent: "claude", text: "Blue or gray?", choices: [])
        let subject = bridge()
        let first = try replyObject(subject.handle(message: ["id": 1, "method": "questions.answer", "params": ["id": question.id, "text": "Blue"]]))
        XCTAssertEqual((first["result"] as? [String: Any])?["answered"] as? Bool, true)
        XCTAssertEqual(Questions.get(id: question.id)?.answer, "Blue")
        let second = subject.handle(message: ["id": 2, "method": "questions.answer", "params": ["id": question.id, "text": "Gray"]])
        XCTAssertEqual(try errorCode(second), "not_found")
        XCTAssertEqual(Questions.get(id: question.id)?.answer, "Blue")
    }

    func testQuestionsAnswerRefusesABadIdAndMissingText() throws {
        try? FileManager.default.removeItem(at: Questions.folder)
        let subject = bridge()
        XCTAssertEqual(try errorCode(subject.handle(message: ["id": 1, "method": "questions.answer", "params": ["id": "../x", "text": "hi"]])), "not_found")
        XCTAssertEqual(try errorCode(subject.handle(message: ["id": 2, "method": "questions.answer", "params": ["id": UUID().uuidString, "text": "hi"]])), "not_found")
        XCTAssertEqual(try errorCode(subject.handle(message: ["id": 3, "method": "questions.answer", "params": ["id": 5, "text": "hi"]])), "bad_params")
        XCTAssertEqual(try errorCode(subject.handle(message: ["id": 4, "method": "questions.answer", "params": ["id": UUID().uuidString, "text": ""]])), "bad_params")
    }

    func testReadsAndWritesAllowedSettings() throws {
        let subject = bridge()
        let written = try replyObject(subject.handle(message: ["id": 1, "method": "settings.set", "params": ["key": "sounds", "value": false]]))
        XCTAssertEqual((written["result"] as? [String: Any])?["value"] as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "sounds") as? Bool, false)
        let read = try replyObject(subject.handle(message: ["id": 2, "method": "settings.get", "params": ["key": "sounds"]]))
        XCTAssertEqual((read["result"] as? [String: Any])?["value"] as? Bool, false)
    }

    func testReadsAndWritesHoldToTalkAndListenAfterDone() throws {
        let standard = UserDefaults.standard
        let savedHold = standard.object(forKey: "holdToTalk")
        let savedListen = standard.object(forKey: "listenAfterDone")
        defer {
            if let savedHold { standard.set(savedHold, forKey: "holdToTalk") } else { standard.removeObject(forKey: "holdToTalk") }
            if let savedListen { standard.set(savedListen, forKey: "listenAfterDone") } else { standard.removeObject(forKey: "listenAfterDone") }
        }
        let subject = WebBridge(defaults: standard, loadItems: { [] })
        for key in ["holdToTalk", "listenAfterDone"] {
            let written = try replyObject(subject.handle(message: ["id": 2, "method": "settings.set", "params": ["key": key, "value": true]]))
            XCTAssertEqual((written["result"] as? [String: Any])?["value"] as? Bool, true)
            let read = try replyObject(subject.handle(message: ["id": 3, "method": "settings.get", "params": ["key": key]]))
            XCTAssertEqual((read["result"] as? [String: Any])?["value"] as? Bool, true)
        }
        XCTAssertTrue(Prefs.holdToTalk)
        XCTAssertTrue(Prefs.listenAfterDone)
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

    private func routed(_ id: String, project: String?, status: String = "open", hoursAgo: Double? = nil) -> Item {
        var made = item(id, status: status)
        made.project = project
        made.at = hoursAgo.map { Date().addingTimeInterval(-$0 * 3600) }
        return made
    }

    private func live(_ cwd: String, agent: String = "claude", pid: Int32 = 1) -> LiveSession {
        LiveSession(pid: pid, cwd: cwd, agent: agent, started: Date(), lastSeen: Date())
    }

    private let projectList = [Project(name: "zeta", path: "/work/zeta"), Project(name: "Alpha", path: "/work/alpha", aliases: ["a"]),
                               Project(name: "beta", path: "/work/beta")]

    private func projectBridge(items: [Item] = [], live sessions: [LiveSession] = [], projects: [Project]? = nil) -> WebBridge {
        let list = projects ?? projectList
        return WebBridge(defaults: defaults, loadItems: { items },
                         findProject: { text in list.first { $0.path == text || $0.name.lowercased() == text.lowercased() } },
                         loadProjects: { list }, loadLive: { sessions })
    }

    private func result(_ bridge: WebBridge, _ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        let reply = try replyObject(bridge.handle(message: ["id": 1, "method": method, "params": params]))
        return try XCTUnwrap(reply["result"] as? [String: Any])
    }

    private func code(_ bridge: WebBridge, _ method: String, _ params: [String: Any]) throws -> String? {
        try errorCode(bridge.handle(message: ["id": 1, "method": method, "params": params]))
    }

    func testProjectsListPutsLiveFirstWithKeysThenOthersByName() throws {
        let subject = projectBridge(live: [live("/work/zeta", pid: 1), live("/work/new", pid: 2), live("/work/zeta", agent: "codex", pid: 3)])
        let projects = try XCTUnwrap(result(subject, "projects.list")["projects"] as? [[String: Any]])
        XCTAssertEqual(projects.map { $0["path"] as? String }, ["/work/zeta", "/work/new", "/work/alpha", "/work/beta"])
        XCTAssertEqual(projects.map { $0["key"] as? Int }, [1, 2, nil, nil])
        XCTAssertEqual(projects.map { $0["name"] as? String }, ["zeta", "new", "Alpha", "beta"])
    }

    func testProjectsListGivesKeysToTheFirstNineLiveProjectsOnly() throws {
        let sessions = (1...10).map { live("/work/p\($0)", pid: Int32($0)) }
        let projects = try XCTUnwrap(result(projectBridge(live: sessions, projects: []), "projects.list")["projects"] as? [[String: Any]])
        XCTAssertEqual(projects.count, 10)
        XCTAssertEqual(projects.map { $0["key"] as? Int }, [1, 2, 3, 4, 5, 6, 7, 8, 9, nil])
        XCTAssertEqual(projects.last?["live"] as? Bool, true)
    }

    func testProjectsListShowsLiveFlagAgentsAndAliases() throws {
        let subject = projectBridge(live: [live("/work/zeta", agent: "claude", pid: 1), live("/work/zeta", agent: "codex", pid: 2),
                                           live("/work/zeta", agent: "claude", pid: 3)])
        let projects = try XCTUnwrap(result(subject, "projects.list")["projects"] as? [[String: Any]])
        XCTAssertEqual(projects[0]["live"] as? Bool, true)
        XCTAssertEqual(projects[0]["agents"] as? [String], ["claude", "codex"])
        let alpha = try XCTUnwrap(projects.first { $0["path"] as? String == "/work/alpha" })
        XCTAssertEqual(alpha["live"] as? Bool, false)
        XCTAssertEqual(alpha["agents"] as? [String], [])
        XCTAssertEqual(alpha["aliases"] as? [String], ["a"])
    }

    func testProjectsListCountsOpenAndInProgressItemsPerProject() throws {
        let items = [routed("a#1", project: "/work/alpha"), routed("a#2", project: "/work/alpha"),
                     routed("a#3", project: "/work/alpha", status: "in_progress"), routed("a#4", project: "/work/alpha", status: "done"),
                     routed("b#1", project: "/work/beta"), routed("c#1", project: nil)]
        let projects = try XCTUnwrap(result(projectBridge(items: items), "projects.list")["projects"] as? [[String: Any]])
        let alpha = try XCTUnwrap(projects.first { $0["path"] as? String == "/work/alpha" })
        let beta = try XCTUnwrap(projects.first { $0["path"] as? String == "/work/beta" })
        let zeta = try XCTUnwrap(projects.first { $0["path"] as? String == "/work/zeta" })
        XCTAssertEqual(alpha["open"] as? Int, 2)
        XCTAssertEqual(alpha["inProgress"] as? Int, 1)
        XCTAssertEqual(beta["open"] as? Int, 1)
        XCTAssertEqual(zeta["open"] as? Int, 0)
        XCTAssertEqual(zeta["inProgress"] as? Int, 0)
    }

    func testItemsListFiltersByProjectNameAndByPath() throws {
        let items = [routed("a#1", project: "/work/alpha"), routed("b#1", project: "/work/beta"), routed("c#1", project: nil)]
        let subject = projectBridge(items: items)
        for text in ["alpha", "/work/alpha"] {
            let found = try XCTUnwrap(result(subject, "items.list", ["project": text])["items"] as? [[String: Any]])
            XCTAssertEqual(found.map { $0["id"] as? String }, ["a#1"])
        }
    }

    func testItemsListProjectNoneKeepsItemsWithNoProject() throws {
        let items = [routed("a#1", project: "/work/alpha"), routed("c#1", project: nil)]
        let found = try XCTUnwrap(result(projectBridge(items: items), "items.list", ["project": "none"])["items"] as? [[String: Any]])
        XCTAssertEqual(found.map { $0["id"] as? String }, ["c#1"])
    }

    func testItemsListUnknownProjectIsNotFoundAndWrongKindIsBadParams() throws {
        let subject = projectBridge(items: [routed("a#1", project: "/work/alpha")])
        XCTAssertEqual(try code(subject, "items.list", ["project": "nowhere"]), "not_found")
        XCTAssertEqual(try code(subject, "items.list", ["project": 5]), "bad_params")
    }

    func testItemsListMaxAgeHoursKeepsRecentItemsAndDropsOldOnes() throws {
        let items = [routed("new#1", project: nil, hoursAgo: 1), routed("old#1", project: nil, hoursAgo: 30), routed("nodate#1", project: nil)]
        let subject = projectBridge(items: items)
        let day = try XCTUnwrap(result(subject, "items.list", ["maxAgeHours": 24])["items"] as? [[String: Any]])
        XCTAssertEqual(day.map { $0["id"] as? String }, ["new#1"])
        let week = try XCTUnwrap(result(subject, "items.list", ["maxAgeHours": 24.5 * 7])["items"] as? [[String: Any]])
        XCTAssertEqual(week.map { $0["id"] as? String }, ["new#1", "old#1"])
    }

    func testItemsListBadMaxAgeHoursIsBadParams() throws {
        let subject = projectBridge(items: [routed("a#1", project: nil, hoursAgo: 1)])
        let badValues: [Any] = [0, -3, "24", true, NSNull()]
        for value in badValues {
            XCTAssertEqual(try code(subject, "items.list", ["maxAgeHours": value]), "bad_params")
        }
    }

    func testItemsListGroupByProjectGivesGroupsLiveFirstNoProjectLastNewestFirst() throws {
        let items = [routed("b#1", project: "/work/beta", hoursAgo: 5), routed("z#1", project: "/work/zeta", hoursAgo: 9),
                     routed("z#2", project: "/work/zeta", hoursAgo: 2), routed("z#3", project: "/work/zeta"),
                     routed("n#1", project: nil, hoursAgo: 1), routed("a#1", project: "/work/alpha", hoursAgo: 3),
                     routed("u#1", project: "/work/unknown", hoursAgo: 4)]
        let subject = projectBridge(items: items, live: [live("/work/zeta")])
        let groups = try XCTUnwrap(result(subject, "items.list", ["groupBy": "project"])["groups"] as? [[String: Any]])
        let paths = groups.map { ($0["project"] as? [String: Any])?["path"] as? String }
        XCTAssertEqual(paths, ["/work/zeta", "/work/alpha", "/work/beta", "/work/unknown", nil])
        XCTAssertTrue(groups.last?["project"] is NSNull)
        XCTAssertEqual(((groups[0]["project"] as? [String: Any])?["name"]) as? String, "zeta")
        let zetaIds = try XCTUnwrap(groups[0]["items"] as? [[String: Any]]).map { $0["id"] as? String }
        XCTAssertEqual(zetaIds, ["z#2", "z#1", "z#3"])
    }

    func testItemsListGroupByWorksWithStatusProjectAndAgeFilters() throws {
        let items = [routed("a#1", project: "/work/alpha", hoursAgo: 1), routed("a#2", project: "/work/alpha", status: "done", hoursAgo: 1),
                     routed("a#3", project: "/work/alpha", hoursAgo: 50), routed("b#1", project: "/work/beta", hoursAgo: 1)]
        let params: [String: Any] = ["groupBy": "project", "status": "open", "project": "alpha", "maxAgeHours": 24]
        let groups = try XCTUnwrap(result(projectBridge(items: items), "items.list", params)["groups"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(try XCTUnwrap(groups[0]["items"] as? [[String: Any]]).map { $0["id"] as? String }, ["a#1"])
    }

    func testItemsListBadGroupByIsBadParams() throws {
        let subject = projectBridge(items: [routed("a#1", project: nil)])
        XCTAssertEqual(try code(subject, "items.list", ["groupBy": "status"]), "bad_params")
        XCTAssertEqual(try code(subject, "items.list", ["groupBy": 1]), "bad_params")
    }

    func testItemsListWithoutNewParamsKeepsTheQueueOrderAndShape() throws {
        let items = [routed("a#1", project: "/work/alpha", hoursAgo: 9), routed("b#1", project: "/work/beta", hoursAgo: 1)]
        let out = try result(projectBridge(items: items), "items.list")
        XCTAssertNil(out["groups"])
        XCTAssertEqual((out["items"] as? [[String: Any]])?.map { $0["id"] as? String }, ["a#1", "b#1"])
    }
}
