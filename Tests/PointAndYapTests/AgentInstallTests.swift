import XCTest
@testable import PointAndYap

/// F1: fresh install. Every file and folder here is a temp one; nothing touches the real home.
final class AgentInstallTests: XCTestCase {
    private var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("agent-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temp)
    }

    func testCandidatesIncludeTheNewPlaces() {
        let list = AgentInstall.cliCandidates(home: "/h")
        for path in ["/h/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude", "/h/.claude/local/claude",
                     "/h/.npm-global/bin/claude", "/h/.bun/bin/claude", "/h/.volta/bin/claude"] {
            XCTAssertTrue(list.contains(path), path)
        }
    }

    func testResolveTakesFirstExecutableCandidateWithoutAskingTheShell() {
        var asked = false
        let found = AgentInstall.resolveCLI(candidates: ["/a/claude", "/b/claude", "/c/claude"],
                                            isExecutable: { $0 == "/b/claude" || $0 == "/c/claude" },
                                            shellLookup: { asked = true; return "/x/claude" })
        XCTAssertEqual(found?.path, "/b/claude")
        XCTAssertFalse(asked)
    }

    func testResolveFallsBackToShellAnswerOnlyWhenAbsoluteAndExecutable() {
        let executable: (String) -> Bool = { $0 == "/shell/claude" }
        XCTAssertEqual(AgentInstall.resolveCLI(candidates: ["/a/claude"], isExecutable: executable,
                                               shellLookup: { "/shell/claude\n" })?.path, "/shell/claude")
        XCTAssertNil(AgentInstall.resolveCLI(candidates: ["/a/claude"], isExecutable: executable,
                                             shellLookup: { "alias claude='something'" }))
        XCTAssertNil(AgentInstall.resolveCLI(candidates: [], isExecutable: { _ in true }, shellLookup: { "claude" }))
        XCTAssertNil(AgentInstall.resolveCLI(candidates: ["/a/claude"], isExecutable: executable,
                                             shellLookup: { "/not/executable/claude" }))
        XCTAssertNil(AgentInstall.resolveCLI(candidates: [], isExecutable: executable, shellLookup: { nil }))
    }

    func testMergeAddsOneStopEntryAndKeepsEveryOtherKey() throws {
        let settings: [String: Any] = [
            "model": "opus",
            "permissions": ["allow": ["Bash(ls)"]],
            "hooks": [
                "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "check.sh"]]]],
                "Stop": [["hooks": [["type": "command", "command": "other-stop.sh"]]]],
            ],
        ]
        let merged = try XCTUnwrap(AgentInstall.mergingStopHook(into: settings))
        XCTAssertEqual(merged["model"] as? String, "opus")
        XCTAssertNotNil(merged["permissions"])
        let hooks = try XCTUnwrap(merged["hooks"] as? [String: Any])
        XCTAssertNotNil(hooks["PreToolUse"])
        let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stop.count, 2)
        let added = try XCTUnwrap((stop[1]["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(added["type"] as? String, "command")
        XCTAssertEqual(added["command"] as? String, "\"/Applications/Pointroo.app/Contents/MacOS/Pointroo\" --hook-stop")
    }

    func testMergeOnEmptySettingsCreatesTheShape() throws {
        let merged = try XCTUnwrap(AgentInstall.mergingStopHook(into: [:]))
        let stop = try XCTUnwrap((merged["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        XCTAssertEqual(stop.count, 1)
    }

    func testMergeDoesNothingWhenOurHookIsThereInEitherShape() {
        for command in ["\"/Applications/Pointroo.app/Contents/MacOS/Pointroo\" --hook-stop",
                        "/Applications/Pointroo.app/Contents/MacOS/Pointroo --hook-stop"] {
            let settings: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": command]]]]]]
            XCTAssertNil(AgentInstall.mergingStopHook(into: settings), command)
        }
    }

    func testMergeLeavesUnexpectedShapesAlone() {
        XCTAssertNil(AgentInstall.mergingStopHook(into: ["hooks": "nope"]))
        XCTAssertNil(AgentInstall.mergingStopHook(into: ["hooks": ["Stop": "nope"]]))
    }

    func testStopHookWritesMergedFileAndBacksUpFirst() throws {
        let settings = temp.appendingPathComponent("settings.json")
        let backups = temp.appendingPathComponent("backups")
        let original = #"{"model":"opus","env":{"A":"1"}}"#
        try original.write(to: settings, atomically: true, encoding: .utf8)
        AgentInstall.stopHook(settings: settings, backups: backups, log: { _ in })
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        XCTAssertEqual(written["model"] as? String, "opus")
        XCTAssertNotNil((written["hooks"] as? [String: Any])?["Stop"])
        let saved = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(try String(contentsOf: backups.appendingPathComponent(saved[0]), encoding: .utf8), original)

        let afterFirst = try Data(contentsOf: settings)
        AgentInstall.stopHook(settings: settings, backups: backups, log: { _ in })
        XCTAssertEqual(try Data(contentsOf: settings), afterFirst, "second run changes nothing")
    }

    func testStopHookLeavesBadJsonAlone() throws {
        let settings = temp.appendingPathComponent("settings.json")
        let backups = temp.appendingPathComponent("backups")
        try "{ not json".write(to: settings, atomically: true, encoding: .utf8)
        var lines: [String] = []
        AgentInstall.stopHook(settings: settings, backups: backups, log: { lines.append($0) })
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), "{ not json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backups.path))
        XCTAssertEqual(lines.count, 1)
    }

    func testStopHookCreatesFileOnlyWhenFolderExists() throws {
        let missingFolder = temp.appendingPathComponent("nope/settings.json")
        AgentInstall.stopHook(settings: missingFolder, backups: temp.appendingPathComponent("b"), log: { _ in })
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingFolder.path))

        let present = temp.appendingPathComponent("settings.json")
        AgentInstall.stopHook(settings: present, backups: temp.appendingPathComponent("b"), log: { _ in })
        XCTAssertTrue(FileManager.default.fileExists(atPath: present.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.appendingPathComponent("b").path), "nothing to back up")
    }

    func testSkillsFolderIsMadeWhenClaudeFolderExists() throws {
        let home = temp.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude"), withIntermediateDirectories: true)
        AgentInstall.linkSkills(home: home, skillPath: "/Applications/Pointroo.app/Contents/Resources/skill/pointroo", log: { _ in })
        let link = home.appendingPathComponent(".claude/skills/pointroo").path
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link),
                       "/Applications/Pointroo.app/Contents/Resources/skill/pointroo")
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".agents").path))
    }

    func testNothingIsMadeWhenClaudeFolderIsMissing() throws {
        let home = temp.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        AgentInstall.linkSkills(home: home, skillPath: "/x/skill/pointroo", log: { _ in })
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude").path))
    }

    func testAskAgainOnActivateOnlyWhileUnanswered() throws {
        let suite = "agent-install-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(AgentInstall.shouldAskAgainOnActivate(defaults: defaults))
        defaults.set(true, forKey: "agentsAsked")
        XCTAssertFalse(AgentInstall.shouldAskAgainOnActivate(defaults: defaults))
        defaults.removeObject(forKey: "agentsAsked")
        defaults.set(false, forKey: "connectAgents")
        XCTAssertFalse(AgentInstall.shouldAskAgainOnActivate(defaults: defaults))
    }

    func testPortPickSkipsEveryBusyPortAndSavesTheFirstFreeOne() {
        var saved: Int?
        var restarted: UInt16?
        var installs = 0
        let result = MCPPort.useAnother(isBusy: { [6742, 6743, 6744].contains($0) }, restart: { restarted = $0; return nil },
                                        install: { installs += 1 }, save: { saved = $0 }, current: 6742)
        XCTAssertEqual(result, .success(6745))
        XCTAssertEqual(saved, 6745)
        XCTAssertEqual(restarted, 6745)
        XCTAssertEqual(installs, 1)
    }

    func testPrewarmGateAllowsEachLocaleOnce() {
        let gate = Transcriber.PrewarmGate()
        XCTAssertTrue(gate.claim("en_US"))
        XCTAssertFalse(gate.claim("en_US"))
        XCTAssertTrue(gate.claim("de_DE"))
    }
}
