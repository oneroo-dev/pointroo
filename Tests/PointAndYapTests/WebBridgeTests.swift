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

    private let sampleStatus = AppStatus(mcpRunning: true, mcpPort: 6742, mcpText: "Shared MCP server: running", sessions: 2,
                                         agents: ["claude", "codex"], microphone: true, screenRecording: false, accessibility: true)

    func testStatusGetReturnsTheStatusShape() throws {
        let subject = WebBridge(defaults: defaults, loadStatus: { self.sampleStatus })
        let status = try XCTUnwrap(result(subject, "status.get")["status"] as? [String: Any])
        XCTAssertEqual(status["mcpRunning"] as? Bool, true)
        XCTAssertEqual(status["mcpPort"] as? Int, 6742)
        XCTAssertEqual(status["mcpText"] as? String, "Shared MCP server: running")
        XCTAssertEqual(status["sessions"] as? Int, 2)
        XCTAssertEqual(status["agents"] as? [String], ["claude", "codex"])
        XCTAssertEqual(status["microphone"] as? Bool, true)
        XCTAssertEqual(status["screenRecording"] as? Bool, false)
        XCTAssertEqual(status["accessibility"] as? Bool, true)
    }

    func testAppStatusMakeUsesBoundPortAndDistinctSortedAgents() {
        let running = AppStatus.make(boundPort: 6743, configuredPort: 6742, text: "t",
                                     live: [live("/a", agent: "codex", pid: 1), live("/b", agent: "claude", pid: 2), live("/c", agent: "codex", pid: 3)],
                                     microphone: false, screenRecording: false, accessibility: false)
        XCTAssertTrue(running.mcpRunning)
        XCTAssertEqual(running.mcpPort, 6743)
        XCTAssertEqual(running.sessions, 3)
        XCTAssertEqual(running.agents, ["claude", "codex"])
        let stopped = AppStatus.make(boundPort: 0, configuredPort: 6742, text: "t", live: [],
                                     microphone: false, screenRecording: false, accessibility: false)
        XCTAssertFalse(stopped.mcpRunning)
        XCTAssertEqual(stopped.mcpPort, 6742)
    }

    func testPermissionsAskCallsTheClosureForEachKnownName() throws {
        var asked: [String] = []
        let subject = WebBridge(defaults: defaults, askPermission: { asked.append($0) })
        for name in ["microphone", "screenRecording", "accessibility"] {
            XCTAssertEqual(try result(subject, "permissions.ask", ["which": name])["asked"] as? Bool, true)
        }
        XCTAssertEqual(asked, ["microphone", "screenRecording", "accessibility"])
    }

    func testPermissionsAskBadWhichIsBadParams() throws {
        var asked: [String] = []
        let subject = WebBridge(defaults: defaults, askPermission: { asked.append($0) })
        XCTAssertEqual(try code(subject, "permissions.ask", [:]), "bad_params")
        XCTAssertEqual(try code(subject, "permissions.ask", ["which": "camera"]), "bad_params")
        XCTAssertEqual(try code(subject, "permissions.ask", ["which": 3]), "bad_params")
        XCTAssertTrue(asked.isEmpty)
    }

    func testPermissionsAskWithoutAClosureIsNotAvailable() throws {
        XCTAssertEqual(try code(WebBridge(defaults: defaults), "permissions.ask", ["which": "microphone"]), "not_available")
    }

    func testItemsListWithoutNewParamsKeepsTheQueueOrderAndShape() throws {
        let items = [routed("a#1", project: "/work/alpha", hoursAgo: 9), routed("b#1", project: "/work/beta", hoursAgo: 1)]
        let out = try result(projectBridge(items: items), "items.list")
        XCTAssertNil(out["groups"])
        XCTAssertEqual((out["items"] as? [[String: Any]])?.map { $0["id"] as? String }, ["a#1", "b#1"])
    }

    private final class StatusCalls {
        var calls: [(id: String, status: String, note: String?)] = []
        var unrouted: [String] = []
        var copied: [String] = []
    }

    private func statusBridge(_ calls: StatusCalls, outcome: WebBridge.StatusChange = .changed) -> WebBridge {
        WebBridge(defaults: defaults, loadItems: { [] },
                  changeStatus: { calls.calls.append(($0, $1, $2)); return outcome })
    }

    func testDoneReopenAndTrashCallTheStatusClosure() throws {
        let calls = StatusCalls()
        let subject = statusBridge(calls)
        let done = try replyObject(subject.handle(message: ["id": 1, "method": "items.done", "params": ["id": "a#1", "note": "fixed"]]))
        XCTAssertEqual((done["result"] as? [String: Any])?["done"] as? Bool, true)
        let reopened = try replyObject(subject.handle(message: ["id": 2, "method": "items.reopen", "params": ["id": "a#1"]]))
        XCTAssertEqual((reopened["result"] as? [String: Any])?["reopened"] as? Bool, true)
        let trashed = try replyObject(subject.handle(message: ["id": 3, "method": "items.trash", "params": ["id": "a#2"]]))
        XCTAssertEqual((trashed["result"] as? [String: Any])?["trashed"] as? Bool, true)
        XCTAssertEqual(calls.calls.map(\.id), ["a#1", "a#1", "a#2"])
        XCTAssertEqual(calls.calls.map(\.status), ["done", "open", "trashed"])
        XCTAssertEqual(calls.calls.map(\.note), ["fixed", nil, nil])
    }

    func testDoneWithoutANoteOrWithAnEmptyNoteSendsNil() throws {
        let calls = StatusCalls()
        let subject = statusBridge(calls)
        _ = subject.handle(message: ["id": 1, "method": "items.done", "params": ["id": "a#1"]])
        _ = subject.handle(message: ["id": 2, "method": "items.done", "params": ["id": "a#2", "note": ""]])
        XCTAssertEqual(calls.calls.count, 2)
        XCTAssertNil(calls.calls[0].note)
        XCTAssertNil(calls.calls[1].note)
    }

    func testStatusMethodsRefuseBadParamsWithoutCallingTheClosure() throws {
        let calls = StatusCalls()
        let subject = statusBridge(calls)
        for method in ["items.done", "items.reopen", "items.trash"] {
            XCTAssertEqual(try code(subject, method, [:]), "bad_params")
            XCTAssertEqual(try code(subject, method, ["id": ""]), "bad_params")
            XCTAssertEqual(try code(subject, method, ["id": 5]), "bad_params")
        }
        XCTAssertEqual(try code(subject, "items.done", ["id": "a#1", "note": 5]), "bad_params")
        XCTAssertTrue(calls.calls.isEmpty)
    }

    func testStatusMethodsMapMissingAndSaveFailed() throws {
        for method in ["items.done", "items.reopen", "items.trash"] {
            XCTAssertEqual(try code(statusBridge(StatusCalls(), outcome: .missing), method, ["id": "a#1"]), "not_found")
            XCTAssertEqual(try code(statusBridge(StatusCalls(), outcome: .saveFailed), method, ["id": "a#1"]), "not_available")
        }
    }

    func testUnrouteCallsTheClosureAndMapsTheOtherResults() throws {
        let calls = StatusCalls()
        let good = WebBridge(defaults: defaults, loadItems: { [] }, unroute: { calls.unrouted.append($0); return .unrouted })
        let reply = try replyObject(good.handle(message: ["id": 1, "method": "items.unroute", "params": ["id": "a#1"]]))
        XCTAssertEqual((reply["result"] as? [String: Any])?["unrouted"] as? Bool, true)
        XCTAssertEqual(calls.unrouted, ["a#1"])
        func code(_ result: Items.UnrouteResult) throws -> String? {
            let subject = WebBridge(defaults: defaults, loadItems: { [] }, unroute: { _ in result })
            return try errorCode(subject.handle(message: ["id": 1, "method": "items.unroute", "params": ["id": "a#1"]]))
        }
        XCTAssertEqual(try code(.missing), "not_found")
        XCTAssertEqual(try code(.taken), "refused")
        XCTAssertEqual(try code(.saveFailed), "not_available")
        XCTAssertEqual(try self.code(good, "items.unroute", [:]), "bad_params")
        XCTAssertEqual(try self.code(good, "items.unroute", ["id": ""]), "bad_params")
        XCTAssertEqual(calls.unrouted, ["a#1"])
    }

    func testClipboardCopyWritesTheTextAndRefusesBadText() throws {
        let calls = StatusCalls()
        let subject = WebBridge(defaults: defaults, loadItems: { [] }, writeClipboard: { calls.copied.append($0) })
        let reply = try replyObject(subject.handle(message: ["id": 1, "method": "clipboard.copy", "params": ["text": "New in Pointroo"]]))
        XCTAssertEqual((reply["result"] as? [String: Any])?["copied"] as? Bool, true)
        XCTAssertEqual(calls.copied, ["New in Pointroo"])
        XCTAssertEqual(try code(subject, "clipboard.copy", [:]), "bad_params")
        XCTAssertEqual(try code(subject, "clipboard.copy", ["text": ""]), "bad_params")
        XCTAssertEqual(try code(subject, "clipboard.copy", ["text": 5]), "bad_params")
        XCTAssertEqual(calls.copied, ["New in Pointroo"])
    }

    func testItemsListLeavesOutTrashedItemsUnlessAsked() throws {
        let items = [item("a#1"), item("b#1", status: "trashed"), item("c#1", status: "done")]
        let subject = bridge(items)
        let all = try XCTUnwrap(result(subject, "items.list")["items"] as? [[String: Any]])
        XCTAssertEqual(all.map { $0["id"] as? String }, ["a#1", "c#1"])
        let trashed = try XCTUnwrap(result(subject, "items.list", ["status": "trashed"])["items"] as? [[String: Any]])
        XCTAssertEqual(trashed.map { $0["id"] as? String }, ["b#1"])
        let grouped = try XCTUnwrap(result(subject, "items.list", ["groupBy": "project"])["groups"] as? [[String: Any]])
        XCTAssertEqual(grouped.flatMap { ($0["items"] as? [[String: Any]]) ?? [] }.map { $0["id"] as? String }, ["a#1", "c#1"])
    }

    func testStartDragCallsTheClosureAndWithoutOneIsNotAvailable() throws {
        let calls = StatusCalls()
        let subject = WebBridge(defaults: defaults, loadItems: { [] }, startDrag: { calls.unrouted.append("drag") })
        XCTAssertEqual(try result(subject, "window.startDrag")["dragging"] as? Bool, true)
        XCTAssertEqual(calls.unrouted, ["drag"])
        XCTAssertEqual(try code(WebBridge(defaults: defaults), "window.startDrag", [:]), "not_available")
    }

    func testUseAnotherPortCallsTheClosureOnceAndWithoutOneIsNotAvailable() throws {
        var calls = 0
        let subject = WebBridge(defaults: defaults, loadItems: { [] }, useAnotherPort: { calls += 1 })
        XCTAssertEqual(try result(subject, "server.useAnotherPort")["asked"] as? Bool, true)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try code(WebBridge(defaults: defaults), "server.useAnotherPort", [:]), "not_available")
    }

    func testCheckUpdatesCallsTheClosureOnceAndWithoutOneIsNotAvailable() throws {
        var calls = 0
        let subject = WebBridge(defaults: defaults, loadItems: { [] }, checkUpdates: { calls += 1 })
        XCTAssertEqual(try result(subject, "app.checkUpdates")["asked"] as? Bool, true)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try code(WebBridge(defaults: defaults), "app.checkUpdates", [:]), "not_available")
    }

    func testKitWindowSettingIsAFlagThatDefaultsToOn() throws {
        let subject = bridge()
        let first = try XCTUnwrap(result(subject, "settings.get", ["key": "kitWindow"])["value"] as? Bool)
        XCTAssertTrue(first)
        _ = try result(subject, "settings.set", ["key": "kitWindow", "value": false])
        XCTAssertEqual(defaults.object(forKey: "kitWindow") as? Bool, false)
        XCTAssertEqual(try result(subject, "settings.get", ["key": "kitWindow"])["value"] as? Bool, false)
        XCTAssertEqual(try code(subject, "settings.set", ["key": "kitWindow", "value": "no"]), "bad_params")
    }

    private func doneItem(_ id: String, session: String = "s", at: Date?, by: String? = "claude", note: String? = nil) -> Item {
        var made = Item(id: id, session: session, n: 1, title: "Fix it", body: "body", crops: [], status: "done", at: at)
        made.by = by
        made.note = note
        return made
    }

    func testDoneRecentGivesDoneItemsNewestFirstWithDoneAt() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [
            doneItem("old#1", at: base),
            item("open#1"),
            doneItem("new#1", at: base.addingTimeInterval(600), note: "fixed it"),
            item("trashed#1", status: "trashed"),
            doneItem("undated#1", at: nil),
            doneItem("mid#1", at: base.addingTimeInterval(300)),
        ]
        let entries = try XCTUnwrap(result(bridge(items), "done.recent")["items"] as? [[String: Any]])
        XCTAssertEqual(entries.map { $0["id"] as? String }, ["new#1", "mid#1", "old#1", "undated#1"])
        XCTAssertEqual(entries.first?["doneAt"] as? String, ISO8601DateFormatter().string(from: base.addingTimeInterval(600)))
        XCTAssertEqual(entries.first?["note"] as? String, "fixed it")
        XCTAssertEqual(entries.first?["by"] as? String, "claude")
        XCTAssertNil(entries.last?["doneAt"])
    }

    func testDoneRecentLimitDefaultsToTenAndIsChecked() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let items = (0..<60).map { doneItem("d\($0)#1", at: base.addingTimeInterval(Double($0))) }
        let subject = bridge(items)
        XCTAssertEqual((try result(subject, "done.recent")["items"] as? [Any])?.count, 10)
        let three = try XCTUnwrap(result(subject, "done.recent", ["limit": 3])["items"] as? [[String: Any]])
        XCTAssertEqual(three.map { $0["id"] as? String }, ["d59#1", "d58#1", "d57#1"])
        XCTAssertEqual((try result(subject, "done.recent", ["limit": 50])["items"] as? [Any])?.count, 50)
        for bad: Any in [0, 51, -1, 2.5, "5", true] {
            XCTAssertEqual(try code(subject, "done.recent", ["limit": bad]), "bad_params", "\(bad)")
        }
    }

    func testDoneRecentCarriesTheBeforeAndAfterPictureAddresses() throws {
        let sessionId = "done-recent-session"
        let folder = Paths.root.appendingPathComponent(sessionId)
        try? FileManager.default.removeItem(at: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("crops"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("after"), withIntermediateDirectories: true)
        try Data("jpg".utf8).write(to: folder.appendingPathComponent("crops/01.jpg"))
        try Data("jpg".utf8).write(to: folder.appendingPathComponent("after/01.jpg"))
        var withPictures = doneItem("\(sessionId)#1", session: sessionId, at: Date(timeIntervalSince1970: 1_800_000_000))
        withPictures.crops = [folder.appendingPathComponent("crops/01.jpg")]
        withPictures.project = "/work/app"
        let plain = doneItem("plain#1", session: "no-such-session", at: Date(timeIntervalSince1970: 1_700_000_000))
        let entries = try XCTUnwrap(result(bridge([withPictures, plain]), "done.recent")["items"] as? [[String: Any]])
        XCTAssertEqual(entries[0]["cropURLs"] as? [String], [WebImages.url(session: sessionId, relative: "crops/01.jpg")])
        XCTAssertEqual(entries[0]["afterURL"] as? String, WebImages.url(session: sessionId, relative: "after/01.jpg"))
        XCTAssertEqual(entries[0]["project"] as? String, "/work/app")
        XCTAssertNil(entries[1]["afterURL"])
        XCTAssertEqual(entries[1]["cropURLs"] as? [String], [])
    }

    private func writeRecording(_ sessionId: String) throws -> URL {
        let folder = Paths.root.appendingPathComponent(sessionId)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("frames"), withIntermediateDirectories: true)
        let events = """
        {"started":"2026-10-17T14:20:00Z","duration":6,"samples":[],
         "frames":[{"file":"frames/001.jpg","t":0,"display":{"x":0,"y":0,"w":1440,"h":900},"scale":2,"reason":"start"},
                   {"file":"frames/002.jpg","t":3,"display":{"x":0,"y":0,"w":1440,"h":900},"scale":2,"reason":"point"}],
         "points":[
          {"index":0,"t":0.5,"end":1.6,"at":{"x":385,"y":224},"kind":"dwell","app":"Example","window":"Settings","url":"https://example.com/a",
           "element":{"role":"AXButton","title":"Save","path":["AXApplication 'Example'"]}},
          {"index":1,"t":2,"end":3,"at":{"x":10,"y":20},"kind":"dwell"}]}
        """
        try Data(events.utf8).write(to: folder.appendingPathComponent("events.json"))
        let words = #"[{"text":"Make","start":0.2,"end":0.4},{"text":"it","start":0.4,"end":0.5},{"text":"blue.","start":0.5,"end":0.9}]"#
        try Data(words.utf8).write(to: folder.appendingPathComponent("transcript.json"))
        try Data("jpg".utf8).write(to: folder.appendingPathComponent("frames/001.jpg"))
        return folder
    }

    func testSessionGetReadsAWholeRecording() throws {
        let sessionId = "session-get-session"
        let folder = try writeRecording(sessionId)
        defer { try? FileManager.default.removeItem(at: folder) }
        let reply = try result(bridge(), "session.get", ["session": sessionId])
        XCTAssertEqual(reply["session"] as? String, sessionId)
        XCTAssertEqual(reply["started"] as? String, "2026-10-17T14:20:00Z")
        XCTAssertEqual(reply["duration"] as? Double, 6)
        let said = try XCTUnwrap(reply["said"] as? [[String: Any]])
        XCTAssertEqual(said.map { $0["text"] as? String }, ["Make", "it", "blue."])
        XCTAssertEqual(said[2]["start"] as? Double, 0.5)
        XCTAssertEqual(said[2]["end"] as? Double, 0.9)
        let points = try XCTUnwrap(reply["points"] as? [[String: Any]])
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[0]["at"] as? Double, 0.5)
        XCTAssertEqual(points[0]["x"] as? Double, 385)
        XCTAssertEqual(points[0]["y"] as? Double, 224)
        XCTAssertEqual(points[0]["app"] as? String, "Example")
        XCTAssertEqual(points[0]["window"] as? String, "Settings")
        XCTAssertEqual(points[0]["url"] as? String, "https://example.com/a")
        XCTAssertEqual(points[0]["element"] as? String, "AXButton \"Save\"")
        XCTAssertNil(points[1]["app"])
        XCTAssertNil(points[1]["element"])
        XCTAssertEqual(reply["frames"] as? [String], [WebImages.url(session: sessionId, relative: "frames/001.jpg")], "only frames that exist")
        XCTAssertEqual(reply["items"] as? [String], ["\(sessionId)#1"])
    }

    func testSessionGetRefusesBadNamesAndMissingRecordings() throws {
        let subject = bridge()
        for bad: Any in ["../etc", "a/b", "..", "x..y", "", 5] {
            XCTAssertEqual(try code(subject, "session.get", ["session": bad]), "bad_params", "\(bad)")
        }
        XCTAssertEqual(try code(subject, "session.get", [:]), "bad_params")
        XCTAssertEqual(try code(subject, "session.get", ["session": "no-such-recording"]), "not_found")
    }

    private func snoozeBridge(at clock: TestClock) -> WebBridge {
        WebBridge(defaults: defaults, loadItems: { [] }, now: { clock.date })
    }

    private final class TestClock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    func testQuestionsLaterHidesTheQuestionUntilTheTimeThenBringsItBack() throws {
        try? FileManager.default.removeItem(at: Questions.folder)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = TestClock(start)
        let question = Questions.ask(project: "alpha", cwd: "/w/alpha", agent: "claude", text: "Blue or gray?", choices: [], now: start)
        let subject = snoozeBridge(at: clock)
        let reply = try result(subject, "questions.later", ["id": question.id, "minutes": 10])
        XCTAssertEqual(reply["snoozed"] as? Bool, true)
        XCTAssertEqual(reply["until"] as? Double, start.addingTimeInterval(600).timeIntervalSince1970)
        XCTAssertEqual((try result(subject, "questions.list")["questions"] as? [Any])?.count, 0)
        clock.date = start.addingTimeInterval(599)
        XCTAssertEqual((try result(subject, "questions.list")["questions"] as? [Any])?.count, 0)
        clock.date = start.addingTimeInterval(600)
        let back = try XCTUnwrap(result(subject, "questions.list")["questions"] as? [[String: Any]])
        XCTAssertEqual(back.map { $0["id"] as? String }, [question.id])
        XCTAssertNil(Questions.get(id: question.id)?.answer)
    }

    func testQuestionsLaterDefaultsToThirtyMinutes() throws {
        try? FileManager.default.removeItem(at: Questions.folder)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let question = Questions.ask(project: "alpha", cwd: "/w/alpha", agent: "claude", text: "Which?", choices: [], now: start)
        let reply = try result(snoozeBridge(at: TestClock(start)), "questions.later", ["id": question.id])
        XCTAssertEqual(reply["until"] as? Double, start.addingTimeInterval(1800).timeIntervalSince1970)
    }

    func testQuestionsLaterChecksMinutesAndTheQuestion() throws {
        try? FileManager.default.removeItem(at: Questions.folder)
        let question = Questions.ask(project: "alpha", cwd: "/w/alpha", agent: "claude", text: "Which?", choices: [])
        let subject = bridge()
        for bad: Any in [0, 1441, -5, 1.5, "30", false] {
            XCTAssertEqual(try code(subject, "questions.later", ["id": question.id, "minutes": bad]), "bad_params", "\(bad)")
        }
        XCTAssertEqual(try code(subject, "questions.later", [:]), "bad_params")
        XCTAssertEqual(try code(subject, "questions.later", ["id": ""]), "bad_params")
        XCTAssertEqual(try code(subject, "questions.later", ["id": UUID().uuidString]), "not_found")
        XCTAssertEqual(try code(subject, "questions.later", ["id": "../x"]), "not_found")
        XCTAssertEqual((try result(subject, "questions.list")["questions"] as? [Any])?.count, 1, "bad calls snooze nothing")
        _ = Questions.answer(id: question.id, text: "Blue")
        XCTAssertEqual(try code(subject, "questions.later", ["id": question.id]), "not_found", "an answered question cannot be snoozed")
        XCTAssertEqual(try code(subject, "questions.later", ["id": question.id, "minutes": 1440]), "not_found")
    }

    func testQuestionsLaterAcceptsTheLargestAllowedMinutes() throws {
        try? FileManager.default.removeItem(at: Questions.folder)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let question = Questions.ask(project: "alpha", cwd: "/w/alpha", agent: "claude", text: "Which?", choices: [], now: start)
        let reply = try result(snoozeBridge(at: TestClock(start)), "questions.later", ["id": question.id, "minutes": 1440])
        XCTAssertEqual(reply["until"] as? Double, start.addingTimeInterval(86400).timeIntervalSince1970)
        XCTAssertEqual(try result(snoozeBridge(at: TestClock(start)), "questions.later", ["id": question.id, "minutes": 1])["snoozed"] as? Bool, true)
    }
}
