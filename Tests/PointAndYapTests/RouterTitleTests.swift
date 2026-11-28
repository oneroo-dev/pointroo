import XCTest
@testable import PointAndYap

/// R39: routing by window title for a project that only has a Claude Code session, and never voting for the Claude app.
final class RouterTitleTests: XCTestCase {
    override class func setUp() { _ = PointAndYapTests.root }

    private func point(url: String? = nil, window: String? = nil) -> PointEvent {
        PointEvent(index: 0, t: 0, end: 1, at: Pt(x: 0, y: 0), kind: "dwell", app: "Claude", bundleID: nil,
                   window: window, url: url, element: nil, frame: nil)
    }

    private func entry(pid: Int, cwd: String, hostSessionId: String? = nil) -> ClaudeSessionEntry {
        ClaudeSessionEntry(pid: pid, sessionId: "session-\(pid)", hostSessionId: hostSessionId, name: nil,
                           messagingSocketPath: nil, status: nil, cwd: cwd)
    }

    func testTitleRoutesToProjectThatComesOnlyFromTheClaudeRegistry() {
        let pointroo = Project(name: "pointroo", path: "/Users/x/Workspace/pointroo", hosts: ["claude.ai"])
        let known = Projects.known(file: [pointroo], live: [],
                                   claude: [entry(pid: 1, cwd: "/Users/x/Workspace/tinkeroo")], owners: [:])
        XCTAssertEqual(known.map(\.name), ["pointroo", "tinkeroo"])
        let result = Router.route(words: ["fix", "this"], points: [point(window: "Tinkeroo \u{00B7} h2-project")], projects: known)
        XCTAssertEqual(result, Router.Result(path: "/Users/x/Workspace/tinkeroo", how: "screen"))
    }

    func testClaudeAppHostNeverMatches() {
        let project = Project(name: "pointroo", path: "/work/pointroo", hosts: ["claude.ai"])
        XCTAssertFalse(Router.matches(point(url: "https://claude.ai/x"), project))
        XCTAssertFalse(Router.matches(point(url: "https://www.claude.ai/chat"), project))
        XCTAssertFalse(Router.matches(point(window: "Claude"), Project(name: "claude", path: "/work/claude")))
        XCTAssertNil(Router.relatedProject([point(url: "https://claude.ai/x", window: "Claude")],
                                           [Project(name: "claude", path: "/work/claude")]))
        XCTAssertTrue(Router.isClaudeAppHost("claude.ai:443"))
        XCTAssertFalse(Router.isClaudeAppHost("notclaude.ai"))
        XCTAssertTrue(Router.isClaudeAppWindow("  CLAUDE "))
        XCTAssertFalse(Router.isClaudeAppWindow("Claude Code docs"))
    }

    func testLearnNeverStoresTheClaudeApp() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("r39-learn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let projectsFile = directory.appendingPathComponent("projects.json")
        let target = Project(name: "learnme", path: "/work/learnme")

        let onClaudeUrl = SessionEvents(started: Date(), duration: 1, samples: [],
                                        points: [point(url: "https://claude.ai/chat/1", window: "Claude")], frames: [])
        try JSONEncoder.pretty.encode(onClaudeUrl).write(to: directory.appendingPathComponent("events.json"))
        Projects.learn(from: directory, project: target, file: projectsFile)
        var learned = try XCTUnwrap(Projects.load(from: projectsFile).first { $0.path == "/work/learnme" })
        XCTAssertEqual(learned.hosts, [])
        XCTAssertEqual(learned.titles, [])

        let onClaudeTitle = SessionEvents(started: Date(), duration: 1, samples: [],
                                          points: [point(window: " claude ")], frames: [])
        try JSONEncoder.pretty.encode(onClaudeTitle).write(to: directory.appendingPathComponent("events.json"))
        Projects.learn(from: directory, project: target, file: projectsFile)
        learned = try XCTUnwrap(Projects.load(from: projectsFile).first { $0.path == "/work/learnme" })
        XCTAssertEqual(learned.titles, [])
    }

    func testFileUrlInsideAProjectFolderMatchesThatProjectOnly() {
        let tinkeroo = Project(name: "tinkeroo", path: "/Users/x/Workspace/tinkeroo")
        let sibling = Project(name: "tinkeroo-extra", path: "/Users/x/Workspace/tinkeroo-extra")
        let pointed = point(url: "file:///Users/x/Workspace/tinkeroo/a.html")
        XCTAssertTrue(Router.matches(pointed, tinkeroo))
        XCTAssertFalse(Router.matches(pointed, sibling))
        XCTAssertEqual(Router.screenProject([pointed], [sibling, tinkeroo])?.path, tinkeroo.path)
    }

    func testKnownDedupesAFolderFromProjectsFileAndRegistry() {
        let fromFile = Project(name: "tinkeroo", path: "/Users/x/Workspace/tinkeroo")
        let known = Projects.known(file: [fromFile], live: [],
                                   claude: [entry(pid: 1, cwd: "/Users/x/Workspace/tinkeroo/"),
                                            entry(pid: 2, cwd: "/Users/x/Workspace/tinkeroo")],
                                   owners: [:])
        XCTAssertEqual(known, [fromFile])
    }

    func testRegistryWorktreeInsideARepoIsSkipped() {
        let known = Projects.known(file: [], live: [],
                                   claude: [entry(pid: 2, cwd: "/w/pointroo/.claude/worktrees/x"), entry(pid: 1, cwd: "/w/pointroo")],
                                   owners: [:])
        XCTAssertEqual(known.map(\.path), ["/w/pointroo"])
    }

    func testDefaultRegistryFolderIsNotTheRealOneInTests() {
        XCTAssertFalse(SessionWake.defaultFolder.path.contains("/.claude/sessions"))
        XCTAssertTrue(SessionWake.entries(in: SessionWake.defaultFolder).isEmpty)
    }

    func testOwnersKeyNamesTheFolderOfTheOwnerSession() {
        let known = Projects.known(file: [], live: [],
                                   claude: [entry(pid: 7, cwd: "/Users/x/Workspace/h2-project", hostSessionId: "host-7")],
                                   owners: ["tinkeroo": "host-7", "ghost": "missing"])
        XCTAssertEqual(known.map(\.name), ["tinkeroo"])
        XCTAssertEqual(known.first?.path, "/Users/x/Workspace/h2-project")
    }
}
