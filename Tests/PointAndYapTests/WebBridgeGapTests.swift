import XCTest
@testable import PointAndYap

/// T1: bad requests and bad params for the bridge methods, with injected closures and no disk.
final class WebBridgeGapTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override class func setUp() { _ = PointAndYapTests.root }

    override func setUp() {
        suiteName = "WebBridgeGapTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private final class Calls {
        var found: [String] = []
        var rerouted: [String] = []
        var statuses: [String] = []
        var unrouted: [String] = []
        var copied: [String] = []
    }

    private func item(_ id: String) -> Item {
        Item(id: id, session: "s", n: 1, title: "Fix it", body: "body", crops: [], status: "open", at: nil)
    }

    private func bridge(_ calls: Calls = Calls()) -> WebBridge {
        let target = Project(name: "backend", path: "/work/backend")
        return WebBridge(defaults: defaults, loadItems: { [self.item("a#1")] },
                         findProject: { calls.found.append($0); return $0 == "backend" ? target : nil },
                         reroute: { id, _ in calls.rerouted.append(id); return .moved },
                         loadProjects: { [] }, loadLive: { [] },
                         loadStatus: { AppStatus(mcpRunning: false, mcpPort: 1, mcpText: "", sessions: 0, agents: [],
                                                 microphone: false, screenRecording: false, accessibility: false) },
                         changeStatus: { id, _, _ in calls.statuses.append(id); return .changed },
                         unroute: { calls.unrouted.append($0); return .unrouted },
                         writeClipboard: { calls.copied.append($0) })
    }

    private func code(_ subject: WebBridge, _ method: String, _ params: [String: Any]) throws -> String? {
        try T1Support.errorCode(subject.handle(message: ["id": 1, "method": method, "params": params]))
    }

    private func result(_ subject: WebBridge, _ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        let reply = try T1Support.replyObject(subject.handle(message: ["id": 1, "method": method, "params": params]))
        return try XCTUnwrap(reply["result"] as? [String: Any], "\(reply)")
    }

    private let notText: [Any] = [5, true, ["a"], NSNull(), ["k": "v"]]

    func testRequestsThatAreNotWellFormedAreBadRequestsWithANullId() throws {
        let subject = bridge()
        let wrongKinds: [Any] = [["id": 1, "method": 5], ["id": 1, "method": ""], ["id": 1, "method": NSNull()],
                                 ["id": [1], "method": "items.list"], ["id": NSNull(), "method": "items.list"],
                                 ["id": ["k": 1], "method": "items.list"], ["method": "items.list"], ["id": 1], [:] as [String: Any]]
        for message in wrongKinds {
            let script = subject.handle(message: message)
            XCTAssertTrue(script.hasPrefix("window.pointroo.reply(null, "), "\(message)")
            XCTAssertEqual(try T1Support.errorCode(script), "bad_request", "\(message)")
        }
        for text in ["", "{", "[1,2]", "null", #"{"id":1}"#, #"{"id":1,"method":""}"#, #"{"method":"items.list"}"#, #"{"id":null,"method":"items.list"}"#] {
            XCTAssertEqual(try T1Support.errorCode(subject.handle(message: text)), "bad_request", text)
        }
        XCTAssertEqual(try T1Support.errorCode(subject.handle(message: 42)), "bad_request")
        XCTAssertEqual(try T1Support.errorCode(subject.handle(message: [1, 2, 3])), "bad_request")
    }

    func testAnUnknownMethodKeepsTheIdAndMethodNamesAreCaseSensitive() throws {
        let subject = bridge()
        let script = subject.handle(message: ["id": "abc", "method": "Items.List"])
        XCTAssertTrue(script.hasPrefix(#"window.pointroo.reply("abc", "#))
        XCTAssertEqual(try T1Support.errorCode(script), "unknown_method")
        for method in ["items.list ", " items.list", "items", "items.", "settings", "../items.list", "constructor"] {
            XCTAssertEqual(try T1Support.errorCode(subject.handle(message: ["id": 3, "method": method])), "unknown_method", method)
        }
    }

    func testParamsThatAreNotAnObjectAreTreatedAsNoParams() throws {
        let subject = bridge()
        for params: Any in ["x", 5, ["a"], NSNull()] {
            let reply = try T1Support.replyObject(subject.handle(message: ["id": 1, "method": "items.list", "params": params]))
            let items = try XCTUnwrap((reply["result"] as? [String: Any])?["items"] as? [[String: Any]], "\(params)")
            XCTAssertEqual(items.map { $0["id"] as? String }, ["a#1"])
        }
        let script = subject.handle(message: #"{"id":1,"method":"items.list","params":"x"}"#)
        XCTAssertNil(try T1Support.replyObject(script)["error"])
    }

    func testKeysTheMethodDoesNotKnowAreIgnored() throws {
        let subject = bridge()
        let item = try XCTUnwrap(result(subject, "items.get", ["id": "a#1", "bogus": 1, "project": "nowhere"])["item"] as? [String: Any])
        XCTAssertEqual(item["id"] as? String, "a#1")
        let listed = try XCTUnwrap(result(subject, "items.list", ["bogus": true, "colour": "red"])["items"] as? [[String: Any]])
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(try result(subject, "settings.get", ["key": "sounds", "other": 5])["value"] as? Bool, true)
        XCTAssertEqual(try result(subject, "status.get", ["junk": 1]).count, 1)
        XCTAssertEqual((try result(subject, "projects.list", ["junk": 1])["projects"] as? [Any])?.count, 0)
    }

    func testItemsGetWithAnIdThatIsNotTextIsBadParams() throws {
        let subject = bridge()
        for bad in notText + [""] {
            XCTAssertEqual(try code(subject, "items.get", ["id": bad]), "bad_params", "\(bad)")
        }
        XCTAssertEqual(try code(subject, "items.get", [:]), "bad_params")
        XCTAssertEqual(try code(subject, "items.get", ["id": "missing#1"]), "not_found")
    }

    func testRerouteWithBadIdOrProjectNeverLooksUpOrMoves() throws {
        let calls = Calls()
        let subject = bridge(calls)
        for bad in notText + [""] {
            XCTAssertEqual(try code(subject, "items.reroute", ["id": bad, "project": "backend"]), "bad_params", "id \(bad)")
            XCTAssertEqual(try code(subject, "items.reroute", ["id": "a#1", "project": bad]), "bad_params", "project \(bad)")
        }
        XCTAssertEqual(try code(subject, "items.reroute", [:]), "bad_params")
        XCTAssertEqual(try code(subject, "items.reroute", ["project": "backend"]), "bad_params")
        XCTAssertTrue(calls.found.isEmpty)
        XCTAssertTrue(calls.rerouted.isEmpty)
    }

    func testRerouteToAnUnknownProjectNamesLookedUpTextAndMovesNothing() throws {
        let calls = Calls()
        let subject = bridge(calls)
        XCTAssertEqual(try code(subject, "items.reroute", ["id": "a#1", "project": "Backend "]), "not_found", "no trimming, no guessing")
        XCTAssertEqual(try code(subject, "items.reroute", ["id": "a#1", "project": "none"]), "not_found")
        XCTAssertEqual(calls.found, ["Backend ", "none"])
        XCTAssertTrue(calls.rerouted.isEmpty)
        XCTAssertEqual(try result(subject, "items.reroute", ["id": "a#1", "project": "backend"])["moved"] as? Bool, true)
        XCTAssertEqual(calls.rerouted, ["a#1"])
    }

    func testUnrouteDoneReopenAndTrashRefuseIdsThatAreNotTextWithoutCallingTheClosures() throws {
        let calls = Calls()
        let subject = bridge(calls)
        for method in ["items.unroute", "items.done", "items.reopen", "items.trash"] {
            for bad in notText + [""] {
                XCTAssertEqual(try code(subject, method, ["id": bad]), "bad_params", "\(method) \(bad)")
            }
            XCTAssertEqual(try code(subject, method, [:]), "bad_params", method)
        }
        XCTAssertTrue(calls.unrouted.isEmpty)
        XCTAssertTrue(calls.statuses.isEmpty)
    }

    func testDoneNoteMustBeTextButOtherMethodsIgnoreANote() throws {
        let calls = Calls()
        let subject = bridge(calls)
        for bad in [5, true, ["a"], NSNull()] as [Any] {
            XCTAssertEqual(try code(subject, "items.done", ["id": "a#1", "note": bad]), "bad_params", "\(bad)")
        }
        XCTAssertTrue(calls.statuses.isEmpty)
        XCTAssertEqual(try result(subject, "items.reopen", ["id": "a#1", "note": 5])["reopened"] as? Bool, true)
        XCTAssertEqual(try result(subject, "items.trash", ["id": "a#1", "note": ["x"]])["trashed"] as? Bool, true)
        XCTAssertEqual(calls.statuses, ["a#1", "a#1"])
    }

    func testClipboardCopyAcceptsTextThatIsOnlySpacesAndKeepsItWhole() throws {
        let calls = Calls()
        let subject = bridge(calls)
        XCTAssertEqual(try result(subject, "clipboard.copy", ["text": "   "])["copied"] as? Bool, true)
        let long = String(repeating: "line\n", count: 2000)
        XCTAssertEqual(try result(subject, "clipboard.copy", ["text": long])["copied"] as? Bool, true)
        XCTAssertEqual(calls.copied, ["   ", long])
        for bad in [5, true, ["a"], NSNull()] as [Any] {
            XCTAssertEqual(try code(subject, "clipboard.copy", ["text": bad]), "bad_params", "\(bad)")
        }
        XCTAssertEqual(calls.copied.count, 2)
    }

    func testQuestionsAnswerAndLaterRefuseIdsThatAreNotText() throws {
        let subject = bridge()
        for bad in notText + [""] {
            XCTAssertEqual(try code(subject, "questions.answer", ["id": bad, "text": "hi"]), "bad_params", "answer \(bad)")
            XCTAssertEqual(try code(subject, "questions.later", ["id": bad]), "bad_params", "later \(bad)")
        }
        for bad in [5, true, ["a"], NSNull()] as [Any] {
            XCTAssertEqual(try code(subject, "questions.answer", ["id": UUID().uuidString, "text": bad]), "bad_params", "text \(bad)")
        }
    }

    func testItemsListRefusesAStatusThatIsNotOneOfTheFour() throws {
        let subject = bridge()
        for bad in [5, true, ["open"], NSNull(), "", "taken", "OPEN", "open ", "all"] as [Any] {
            XCTAssertEqual(try code(subject, "items.list", ["status": bad]), "bad_params", "\(bad)")
        }
        for good in ["open", "in_progress", "done", "trashed"] {
            XCTAssertNotNil(try result(subject, "items.list", ["status": good])["items"], good)
        }
    }

    func testItemsListRefusesAProjectThatIsNotTextOrIsEmpty() throws {
        let subject = bridge()
        for bad in [5, true, ["a"], NSNull(), ""] as [Any] {
            XCTAssertEqual(try code(subject, "items.list", ["project": bad]), "bad_params", "\(bad)")
        }
    }

    func testItemsListMaxAgeHoursRefusesNumbersThatAreNotUsable() throws {
        let subject = bridge()
        for bad in [0.0, -0.5, "1", ["1"], true, false, NSNull()] as [Any] {
            XCTAssertEqual(try code(subject, "items.list", ["maxAgeHours": bad]), "bad_params", "\(bad)")
        }
        XCTAssertEqual(try code(subject, "items.list", ["maxAgeHours": Double.infinity]), "bad_params")
        XCTAssertNotNil(try result(subject, "items.list", ["maxAgeHours": 0.25])["items"])
    }

    func testSettingsGetWithAKeyThatIsNotAllowedOrNotTextIsRefused() throws {
        let subject = bridge()
        for bad in [5, true, ["sounds"], NSNull(), "", "Sounds", "sounds ", "locale2", "mcpPort", "webDevURL"] as [Any] {
            XCTAssertEqual(try code(subject, "settings.get", ["key": bad]), "refused", "\(bad)")
        }
    }

    func testSettingsGetWithoutAKeyGivesEveryAllowedKeyWithItsDefault() throws {
        let values = try XCTUnwrap(result(bridge(), "settings.get")["values"] as? [String: Any])
        XCTAssertEqual(Set(values.keys), Set(WebBridge.allowedSettings.map(\.key)))
        XCTAssertEqual(values["sounds"] as? Bool, true)
        XCTAssertEqual(values["kitWindow"] as? Bool, true)
        XCTAssertEqual(values["autoSendSingle"] as? Bool, true)
        XCTAssertEqual(values["connectAgents"] as? Bool, false)
        XCTAssertEqual(values["holdToTalk"] as? Bool, false)
        XCTAssertEqual(values["locale"] as? String, "")
    }

    func testSettingsSetWithoutAnAllowedKeyIsRefusedBeforeTheValueIsLookedAt() throws {
        let subject = bridge()
        for bad in [5, true, NSNull(), "", "Sounds", "mcpPort"] as [Any] {
            XCTAssertEqual(try code(subject, "settings.set", ["key": bad, "value": true]), "refused", "\(bad)")
        }
        XCTAssertEqual(try code(subject, "settings.set", ["value": true]), "refused")
        XCTAssertEqual(try code(subject, "settings.set", [:]), "refused")
        XCTAssertNil(defaults.object(forKey: "mcpPort"))
    }

    func testAFlagTakesOnlyARealBoolean() throws {
        let subject = bridge()
        for bad in [1, 0, 1.0, "true", "on", NSNull(), [true]] as [Any] {
            XCTAssertEqual(try code(subject, "settings.set", ["key": "sounds", "value": bad]), "bad_params", "\(bad)")
        }
        XCTAssertEqual(try code(subject, "settings.set", ["key": "sounds"]), "bad_params", "no value at all")
        XCTAssertNil(defaults.object(forKey: "sounds"))
        XCTAssertEqual(try result(subject, "settings.set", ["key": "sounds", "value": false])["value"] as? Bool, false)
        XCTAssertEqual(try result(subject, "settings.set", ["key": "sounds", "value": true])["value"] as? Bool, true)
    }

    func testTheLocaleSettingTakesOnlyAKnownLanguageId() throws {
        let subject = bridge()
        XCTAssertEqual(try result(subject, "settings.set", ["key": "locale", "value": "de-DE"])["value"] as? String, "de-DE")
        XCTAssertEqual(defaults.string(forKey: "locale"), "de-DE")
        for bad in ["xx-XX", "de", "DE-de", " de-DE", true, 5, NSNull(), ["de-DE"]] as [Any] {
            XCTAssertEqual(try code(subject, "settings.set", ["key": "locale", "value": bad]), "bad_params", "\(bad)")
        }
        XCTAssertEqual(try code(subject, "settings.set", ["key": "locale"]), "bad_params")
        XCTAssertEqual(defaults.string(forKey: "locale"), "de-DE", "bad calls change nothing")
        XCTAssertEqual(try result(subject, "settings.set", ["key": "locale", "value": ""])["value"] as? String, "", "empty means same as the Mac")
        XCTAssertEqual(try result(subject, "settings.get", ["key": "locale"])["value"] as? String, "")
    }

    func testWindowStartDragIgnoresParamsAndPermissionsAskNeedsAnExactName() throws {
        let calls = Calls()
        let subject = WebBridge(defaults: defaults, askPermission: { calls.copied.append($0) }, startDrag: { calls.unrouted.append("drag") })
        XCTAssertEqual(try result(subject, "window.startDrag", ["x": 1])["dragging"] as? Bool, true)
        for bad in ["Microphone", "microphone ", "screenrecording", "", "location"] {
            XCTAssertEqual(try code(subject, "permissions.ask", ["which": bad]), "bad_params", bad)
        }
        XCTAssertEqual(try code(subject, "permissions.ask", ["which": ["microphone"]]), "bad_params")
        XCTAssertTrue(calls.copied.isEmpty)
        XCTAssertEqual(calls.unrouted, ["drag"])
    }

    func testEveryMethodAnswersJunkParamsWithOneReplyAndNoCrash() throws {
        let subject = bridge()
        let junk: [String: Any] = ["id": 5, "text": 5, "key": ["a"], "value": NSNull(), "project": true, "status": 3, "note": 1,
                                   "session": 7, "minutes": "x", "limit": "x", "which": 9, "groupBy": 2, "maxAgeHours": "x"]
        let allowed: Set<String> = ["bad_params", "refused", "not_found", "not_available"]
        for method in WebBridge.methods.keys.sorted() {
            let reply = try T1Support.replyObject(subject.handle(message: ["id": method, "method": method, "params": junk]))
            if let error = reply["error"] as? [String: Any] {
                XCTAssertTrue(allowed.contains(error["code"] as? String ?? ""), "\(method) \(error)")
            } else {
                XCTAssertNotNil(reply["result"], method)
            }
        }
    }
}
