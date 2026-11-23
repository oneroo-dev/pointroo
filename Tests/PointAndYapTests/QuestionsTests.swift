import XCTest
@testable import PointAndYap

final class QuestionsTests: XCTestCase {
    override class func setUp() { _ = PointAndYapTests.root; Questions.pollInterval = 0.05 }

    override func setUp() {
        try? FileManager.default.removeItem(at: Questions.folder)
        try? FileManager.default.removeItem(at: Heartbeat.file)
    }

    private func connection(_ cwd: String, open: @escaping () -> Bool = { true }) -> MCPConnection {
        MCPConnection(cwd: cwd, isOpen: open)
    }

    private func text(_ result: [String: Any]) -> String {
        ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
    }

    private func questionFiles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: Questions.folder.path)) ?? []).filter { $0.hasSuffix(".json") }
    }

    private func idFrom(_ reply: String) -> String? {
        reply.components(separatedBy: "question ").dropFirst().first?.components(separatedBy: ")").first
    }

    func testAskListsAsPendingAndAnswerRemovesItFromPending() {
        let question = Questions.ask(project: "alpha", cwd: "/w/alpha", agent: "a", text: "Blue or gray?", choices: ["Blue", "Gray"])
        XCTAssertNotNil(UUID(uuidString: question.id))
        XCTAssertEqual(Questions.pending().map(\.id), [question.id])
        XCTAssertTrue(Questions.answer(id: question.id, text: "Blue"))
        XCTAssertEqual(Questions.get(id: question.id)?.answer, "Blue")
        XCTAssertTrue(Questions.pending().isEmpty)
        XCTAssertFalse(Questions.answer(id: question.id, text: "Gray"), "a second answer does not replace the first")
        XCTAssertEqual(Questions.get(id: question.id)?.answer, "Blue")
    }

    func testChoicesAreCappedAtFour() {
        let question = Questions.ask(project: "p", cwd: "/w/p", agent: "a", text: "q", choices: ["1", "2", "3", "4", "5", "6"])
        XCTAssertEqual(question.choices, ["1", "2", "3", "4"])
    }

    func testPathTraversalIdsAreRefused() {
        XCTAssertNil(Questions.validID("../x"))
        XCTAssertNil(Questions.validID("../../etc/passwd"))
        XCTAssertNil(Questions.get(id: "../x"))
        XCTAssertFalse(Questions.answer(id: "../x", text: "no"))
        let reply = connection("/w/alpha").call("ask_user", ["question_id": "../../x"])
        XCTAssertEqual(reply["isError"] as? Bool, true)
        XCTAssertTrue(questionFiles().isEmpty)
    }

    func testNotRunningWhenThereIsNoHeartbeat() {
        let reply = connection("/w/alpha").call("ask_user", ["question": "Hi?"])
        XCTAssertEqual(text(reply), MCPConnection.notRunningText)
        XCTAssertTrue(questionFiles().isEmpty, "no file is left behind")
    }

    func testNotRunningWhenTheHeartbeatIsOlderThanSixSeconds() {
        Heartbeat.write(now: Date(timeIntervalSinceNow: -7), questions: true)
        let reply = connection("/w/alpha").call("ask_user", ["question": "Hi?"])
        XCTAssertEqual(text(reply), MCPConnection.notRunningText)
        XCTAssertTrue(questionFiles().isEmpty)
    }

    func testNoPanelYetWhenTheHeartbeatSaysQuestionsFalse() {
        Heartbeat.write(questions: false)
        let reply = connection("/w/alpha").call("ask_user", ["question": "Hi?"])
        XCTAssertEqual(text(reply), MCPConnection.noPanelText)
        XCTAssertTrue(questionFiles().isEmpty)
    }

    func testHeartbeatFileFormat() throws {
        Heartbeat.write(now: Date(timeIntervalSince1970: 1_764_000_000.5), questions: false)
        let raw = try String(contentsOf: Heartbeat.file, encoding: .utf8)
        XCTAssertEqual(raw, "{\"questions\":false,\"time\":1764000000.5}")
        XCTAssertEqual(Heartbeat.read(), Heartbeat.Reading(time: Date(timeIntervalSince1970: 1_764_000_000.5), questions: false))
        XCTAssertTrue(Heartbeat.isFresh(now: Date(timeIntervalSince1970: 1_764_000_005)))
        XCTAssertFalse(Heartbeat.isFresh(now: Date(timeIntervalSince1970: 1_764_000_007)))
    }

    func testNoAnswerYetThenQuestionIdReturnsTheStoredAnswer() throws {
        Heartbeat.write(questions: true)
        let agent = connection("/w/alpha")
        let first = text(agent.call("ask_user", ["question": "Which?", "timeout_seconds": 0]))
        XCTAssertTrue(first.hasPrefix("No answer yet (question "), first)
        let id = try XCTUnwrap(idFrom(first))
        XCTAssertTrue(first.contains("question_id \"\(id)\""))
        XCTAssertEqual(text(agent.call("ask_user", ["question_id": id, "timeout_seconds": 0])), first)
        Questions.answer(id: id, text: "Gray")
        XCTAssertEqual(text(agent.call("ask_user", ["question_id": id, "timeout_seconds": 0.0])), "The user answered: \"Gray\"")
    }

    func testAnAnswerGivenWhileWaitingIsReturned() {
        Heartbeat.write(questions: true)
        let agent = connection("/w/alpha")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            if let id = Questions.pending().first?.id { Questions.answer(id: id, text: "Yes") }
        }
        XCTAssertEqual(text(agent.call("ask_user", ["question": "Ok?", "timeout_seconds": 5])), "The user answered: \"Yes\"")
    }

    func testAClosedConnectionStopsTheWaitAndRemovesTheQuestion() {
        Heartbeat.write(questions: true)
        let reply = connection("/w/alpha", open: { false }).call("ask_user", ["question": "Ok?", "timeout_seconds": 5])
        XCTAssertEqual(text(reply), "The connection is closed.")
        XCTAssertTrue(questionFiles().isEmpty)
    }

    func testTwoAgentsInTwoProjectsNeverGetEachOthersAnswers() throws {
        Heartbeat.write(questions: true)
        let alpha = connection("/w/alpha"), beta = connection("/w/beta")
        let alphaId = try XCTUnwrap(idFrom(text(alpha.call("ask_user", ["question": "A?", "timeout_seconds": 0]))))
        let betaId = try XCTUnwrap(idFrom(text(beta.call("ask_user", ["question": "B?", "timeout_seconds": 0]))))
        XCTAssertNotEqual(alphaId, betaId)
        XCTAssertEqual(Set(Questions.pending().map(\.cwd)), ["/w/alpha", "/w/beta"])
        Questions.answer(id: betaId, text: "B-answer")
        XCTAssertTrue(text(alpha.call("ask_user", ["question_id": alphaId, "timeout_seconds": 0])).hasPrefix("No answer yet"))
        XCTAssertEqual(text(beta.call("ask_user", ["question_id": betaId, "timeout_seconds": 0])), "The user answered: \"B-answer\"")
        let crossed = text(alpha.call("ask_user", ["question_id": betaId, "timeout_seconds": 0]))
        XCTAssertFalse(crossed.contains("B-answer"), "another project's question id returns nothing")
    }

    func testMissingQuestionTextIsAnError() {
        Heartbeat.write(questions: true)
        XCTAssertEqual(connection("/w/alpha").call("ask_user", [:])["isError"] as? Bool, true)
    }

    func testCleanupDeletesQuestionsOlderThanADay() {
        let old = Questions.ask(project: "p", cwd: "/w/p", agent: "a", text: "old", choices: [], now: Date(timeIntervalSinceNow: -2 * 86400))
        let fresh = Questions.ask(project: "p", cwd: "/w/p", agent: "a", text: "new", choices: [])
        Questions.cleanup()
        XCTAssertNil(Questions.get(id: old.id))
        XCTAssertNotNil(Questions.get(id: fresh.id))
    }

    func testHeartbeatTimerRunsInCommonModesAndWritesAtOnce() {
        let timer = Heartbeat.start()
        defer { timer.invalidate() }
        XCTAssertTrue(CFRunLoopContainsTimer(CFRunLoopGetMain(), timer, .commonModes))
        XCTAssertTrue(Heartbeat.isFresh())
    }

    func testToolIsListedAndMentionedInTheInstructions() {
        XCTAssertTrue(MCPServer.tools.contains { $0["name"] as? String == "ask_user" })
        XCTAssertTrue(MCPServer.instructions.contains("ask_user"))
    }
}
