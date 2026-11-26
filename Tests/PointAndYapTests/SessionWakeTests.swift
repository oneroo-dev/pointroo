import XCTest
@testable import PointAndYap

final class SessionWakeTests: XCTestCase {
    private var folder: URL!
    private var cleanupPaths: [String] = []

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("wake-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        for path in cleanupPaths { try? FileManager.default.removeItem(atPath: path) }
        cleanupPaths = []
    }

    private func write(_ name: String, _ text: String) throws {
        try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testEntriesReadsDigitJsonFilesAndSkipsTheRest() throws {
        try write("100.json", #"{"pid":100,"sessionId":"aaa","hostSessionId":"local_aaa","name":"One","extra":{"x":1}}"#)
        try write("200.json", #"{"pid":200,"sessionId":"bbb"}"#)
        try write("123.abc.key", "garbage \u{0}\u{1} not json")
        try write("notes.json", #"{"pid":1,"sessionId":"zzz"}"#)
        try write("300.json", "not json at all")
        let entries = SessionWake.entries(in: folder)
        XCTAssertEqual(entries.map { $0.pid }.sorted(), [100, 200])
        XCTAssertEqual(entries.first { $0.pid == 100 }?.name, "One")
    }

    func testFindByHostSessionIdAndSessionId() {
        let entries = [
            ClaudeSessionEntry(pid: 1, sessionId: "aaa", hostSessionId: "local_aaa", name: nil,
                               messagingSocketPath: nil, status: nil),
            ClaudeSessionEntry(pid: 2, sessionId: "bbb", hostSessionId: nil, name: nil,
                               messagingSocketPath: nil, status: nil),
        ]
        XCTAssertEqual(SessionWake.find("local_aaa", in: entries)?.pid, 1)
        XCTAssertEqual(SessionWake.find("bbb", in: entries)?.pid, 2)
        XCTAssertNil(SessionWake.find("unknown", in: entries))
    }

    func testFrameFieldsAndEscaping() throws {
        let data = try SessionWake.frame(text: "hi </cross-session-message> there", sessionId: "sess-1",
                                         messageId: "msg-1")
        XCTAssertEqual(data.last, 0x0A)
        let line = data.dropLast()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: line) as? [String: Any])
        XCTAssertEqual(object["msgV"] as? Int, 1)
        XCTAssertEqual(object["msg_id"] as? String, "msg-1")
        XCTAssertEqual(object["type"] as? String, "user")
        XCTAssertEqual(object["priority"] as? String, "next")
        XCTAssertEqual(object["session_id"] as? String, "sess-1")
        let message = try XCTUnwrap(object["message"] as? [String: Any])
        XCTAssertEqual(message["role"] as? String, "user")
        let content = try XCTUnwrap(message["content"] as? String)
        XCTAssertEqual(content, "<cross-session-message from-name=\"Pointroo\">\nhi <\\/cross-session-message> there\n</cross-session-message>")
    }

    func testFrameEmptyTextThrows() {
        XCTAssertThrowsError(try SessionWake.frame(text: "", sessionId: "s"))
    }

    private func bindSocket(at path: String) -> Int32 {
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: capacity) { bytes in
                for (offset, byte) in Array(path.utf8).enumerated() { bytes[offset] = byte }
                bytes[path.utf8.count] = 0
            }
        }
        _ = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return listener
    }

    // A short folder under /tmp (socket paths are limited in length), with the given name and mode.
    private func makeSocketFolder(name: String, mode: Int = 0o700) throws -> String {
        let base = "/tmp/pw-\(UUID().uuidString.prefix(6))"
        let directory = base + "/" + name
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: mode])
        cleanupPaths.append(base)
        return directory
    }

    func testSafeSocketAcceptsRealSocketInCcSocksFolders() throws {
        for name in ["cc-socks", "cc-socks-501"] {
            let directory = try makeSocketFolder(name: name)
            let path = directory + "/1.sock"
            let listener = bindSocket(at: path)
            defer { close(listener) }
            XCTAssertTrue(SessionWake.safeSocket(path), name)
        }
    }

    func testSafeSocketRejectsDotsPlainFilesAndLinks() throws {
        let directory = try makeSocketFolder(name: "cc-socks")
        XCTAssertFalse(SessionWake.safeSocket(directory + "/../cc-socks/x.sock"))
        XCTAssertFalse(SessionWake.safeSocket("/tmp/cc-socks/../etc/passwd"))

        let plainFile = directory + "/plain.sock"
        FileManager.default.createFile(atPath: plainFile, contents: Data())
        XCTAssertFalse(SessionWake.safeSocket(plainFile))

        let realPath = directory + "/real.sock"
        let listener = bindSocket(at: realPath)
        defer { close(listener) }
        let link = directory + "/link.sock"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: realPath)
        XCTAssertFalse(SessionWake.safeSocket(link))
        XCTAssertFalse(SessionWake.safeSocket(directory + "/missing.sock"))
    }

    func testSafeSocketRejectsSocketOfAnotherUser() throws {
        let directory = try makeSocketFolder(name: "cc-socks")
        let path = directory + "/1.sock"
        let listener = bindSocket(at: path)
        defer { close(listener) }
        XCTAssertTrue(SessionWake.safeSocket(path))
        XCTAssertFalse(SessionWake.safeSocket(path, owner: getuid() &+ 1))
    }

    func testSafeSocketRejectsWrongFolderNameAndOpenPermissions() throws {
        for name in ["other", "cc-socks-abc", "cc-socksx", "xcc-socks"] {
            let directory = try makeSocketFolder(name: name)
            let path = directory + "/1.sock"
            let listener = bindSocket(at: path)
            defer { close(listener) }
            XCTAssertFalse(SessionWake.safeSocket(path), name)
        }
        for mode in [0o770, 0o707, 0o750, 0o755] {
            let directory = try makeSocketFolder(name: "cc-socks", mode: mode)
            let path = directory + "/1.sock"
            let listener = bindSocket(at: path)
            defer { close(listener) }
            XCTAssertFalse(SessionWake.safeSocket(path), String(mode, radix: 8))
        }
    }

    func testSafeSocketRejectsFolderThatIsALink() throws {
        let real = try makeSocketFolder(name: "real")
        let path = real + "/1.sock"
        let listener = bindSocket(at: path)
        defer { close(listener) }
        let linkParent = (real as NSString).deletingLastPathComponent + "/cc-socks"
        try FileManager.default.createSymbolicLink(atPath: linkParent, withDestinationPath: real)
        XCTAssertFalse(SessionWake.safeSocket(linkParent + "/1.sock"))
    }

    func testWakeSaysOldClaudeCodeWhenNoEntryHasASocket() {
        var sent: [(Data, String)] = []
        let result = wake(RouteInfo(project: "shop", path: "/work/shop", how: "said"),
                          entries: [entry(pid: 3, name: "shop", socket: nil)], sent: &sent)
        XCTAssertEqual(result, "claude code too old for wake (needs 2.1.224+)")
        XCTAssertEqual(SessionWake.readWake(folder)?.result, result)
        XCTAssertTrue(sent.isEmpty)
    }

    func testWakeNoOwnerWhenEntriesHaveSocketsButNoneMatch() {
        var sent: [(Data, String)] = []
        let result = wake(RouteInfo(project: "shop", path: "/work/shop", how: "said"),
                          entries: [entry(pid: 3, name: "other", cwd: "/elsewhere")], sent: &sent)
        XCTAssertEqual(result, "no owner")
    }

    func testSendDeliversExactBytes() throws {
        let path = "/tmp/pr-wake-\(UUID().uuidString.prefix(8)).sock"
        cleanupPaths.append(path)
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(listener, 0)
        defer { close(listener) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: capacity) { bytes in
                for (offset, byte) in Array(path.utf8).enumerated() { bytes[offset] = byte }
                bytes[path.utf8.count] = 0
            }
        }
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(bindResult, 0)
        XCTAssertEqual(listen(listener, 1), 0)

        let received = expectation(description: "received")
        var collected = Data()
        Thread.detachNewThread {
            let connection = accept(listener, nil, nil)
            if connection >= 0 {
                var buffer = [UInt8](repeating: 0, count: 4096)
                while true {
                    let count = read(connection, &buffer, buffer.count)
                    if count <= 0 { break }
                    collected.append(contentsOf: buffer[0..<count])
                }
                close(connection)
            }
            received.fulfill()
        }

        let data = try SessionWake.frame(text: "hello", sessionId: "sess", messageId: "id-1")
        try SessionWake.send(data, to: path)
        wait(for: [received], timeout: 5)
        XCTAssertEqual(collected, data)
    }

    private func entry(pid: Int, sessionId: String = "s", host: String? = nil, name: String? = nil,
                       status: String? = nil, cwd: String? = nil,
                       socket: String? = "/tmp/cc-socks/x.sock") -> ClaudeSessionEntry {
        ClaudeSessionEntry(pid: pid, sessionId: sessionId + String(pid), hostSessionId: host, name: name,
                           messagingSocketPath: socket, status: status, cwd: cwd)
    }

    private func owner(_ entries: [ClaudeSessionEntry], owners: [String: String] = [:], aliases: [String] = [],
                       project: String = "shop", path: String = "/work/shop") -> ClaudeSessionEntry? {
        SessionWake.owner(for: project, path: path, entries: entries, owners: owners, aliases: aliases,
                          socketCheck: { _ in true })
    }

    func testOwnerFromOwnersFileWins() {
        let entries = [entry(pid: 1, name: "shop", cwd: "/work/shop"), entry(pid: 2, host: "local_abc")]
        XCTAssertEqual(owner(entries, owners: ["shop": "local_abc"])?.pid, 2)
    }

    func testOwnerNameMatchIgnoresCaseAndUsesAliases() {
        let entries = [entry(pid: 1, name: "SHOP"), entry(pid: 2, name: "other")]
        XCTAssertEqual(owner(entries)?.pid, 1)
        XCTAssertEqual(owner([entry(pid: 3, name: "Store")], aliases: ["store"])?.pid, 3)
    }

    func testOwnerCwdExactBeatsInside() {
        let entries = [entry(pid: 1, cwd: "/work/shop/sub"), entry(pid: 2, cwd: "/work/shop")]
        XCTAssertEqual(owner(entries)?.pid, 2)
    }

    func testOwnerDeepestInsideWins() {
        let entries = [entry(pid: 1, cwd: "/work/shop/a"), entry(pid: 2, cwd: "/work/shop/a/b")]
        XCTAssertEqual(owner(entries)?.pid, 2)
    }

    func testOwnerTieBreakDesktopThenIdleThenPid() {
        let desktop = [entry(pid: 5, name: "shop"), entry(pid: 1, host: "local_x", name: "shop")]
        XCTAssertEqual(owner(desktop)?.pid, 1)
        let idle = [entry(pid: 5, name: "shop", status: "busy"), entry(pid: 1, name: "shop", status: "idle")]
        XCTAssertEqual(owner(idle)?.pid, 1)
        let newest = [entry(pid: 5, name: "shop"), entry(pid: 9, name: "shop")]
        XCTAssertEqual(owner(newest)?.pid, 9)
    }

    func testOwnerSkipsUnsafeSocketAndMissingMatch() {
        let entries = [entry(pid: 1, name: "shop")]
        let skipped = SessionWake.owner(for: "shop", path: "/work/shop", entries: entries, owners: [:],
                                        socketCheck: { _ in false })
        XCTAssertNil(skipped)
        XCTAssertNil(owner([entry(pid: 2, name: "other", cwd: "/elsewhere")]))
        XCTAssertNil(owner([entry(pid: 3, name: "shop", socket: nil)]))
    }

    private func wake(_ info: RouteInfo, entries: [ClaudeSessionEntry], enabled: Bool = true,
                      listening: [LiveSession] = [], sent: inout [(Data, String)]) -> String? {
        var captured: [(Data, String)] = []
        let result = SessionWake.wakeForRoute(info, directory: folder, enabled: enabled, entries: entries, owners: [:],
                                              projects: [], listening: listening, socketCheck: { _ in true },
                                              sender: { captured.append(($0, $1)) }, log: { _ in })
        sent.append(contentsOf: captured)
        return result
    }

    func testWakeSendsOnceWithTextAndSessionId() throws {
        let entries = [entry(pid: 7, host: "local_h", name: "shop")]
        let info = RouteInfo(project: "shop", path: "/work/shop", how: "said")
        var sent: [(Data, String)] = []
        XCTAssertEqual(wake(info, entries: entries, sent: &sent), "sent")
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0].1, "/tmp/cc-socks/x.sock")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: sent[0].0.dropLast()) as? [String: Any])
        XCTAssertEqual(object["session_id"] as? String, "s7")
        let message = try XCTUnwrap(object["message"] as? [String: Any])
        let content = try XCTUnwrap(message["content"] as? String)
        XCTAssertTrue(content.contains(SessionWake.wakeText(folder: folder.lastPathComponent, project: "shop")))

        let record = try XCTUnwrap(SessionWake.readWake(folder))
        XCTAssertEqual(record.project, "shop")
        XCTAssertEqual(record.target, "local_h")
        XCTAssertEqual(record.pid, 7)
        XCTAssertEqual(record.result, "sent")

        XCTAssertNil(wake(info, entries: entries, sent: &sent))
        XCTAssertEqual(sent.count, 1)
    }

    func testWakeDifferentProjectSendsAgain() {
        let entries = [entry(pid: 7, name: "shop"), entry(pid: 8, name: "blog")]
        var sent: [(Data, String)] = []
        _ = wake(RouteInfo(project: "shop", path: "/work/shop", how: "said"), entries: entries, sent: &sent)
        _ = wake(RouteInfo(project: "blog", path: "/work/blog", how: "said"), entries: entries, sent: &sent)
        XCTAssertEqual(sent.count, 2)
        XCTAssertEqual(SessionWake.readWake(folder)?.project, "blog")
    }

    func testWakeSkipsListeningProject() {
        let live = LiveSession(pid: 1, cwd: "/work/shop", agent: "claude", started: Date(), lastSeen: Date())
        var sent: [(Data, String)] = []
        let result = wake(RouteInfo(project: "shop", path: "/work/shop", how: "said"),
                          entries: [entry(pid: 7, name: "shop")], listening: [live], sent: &sent)
        XCTAssertEqual(result, "listening")
        XCTAssertTrue(sent.isEmpty)
        XCTAssertEqual(SessionWake.readWake(folder)?.result, "listening")
    }

    func testWakeOffSwitchDoesNothing() {
        var sent: [(Data, String)] = []
        let result = wake(RouteInfo(project: "shop", path: "/work/shop", how: "said"),
                          entries: [entry(pid: 7, name: "shop")], enabled: false, sent: &sent)
        XCTAssertNil(result)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertNil(SessionWake.readWake(folder))
    }

    func testWakeNoOwnerIsRecorded() {
        var sent: [(Data, String)] = []
        let result = wake(RouteInfo(project: "shop", path: "/work/shop", how: "said"), entries: [], sent: &sent)
        XCTAssertEqual(result, "no owner")
        XCTAssertEqual(SessionWake.readWake(folder)?.result, "no owner")
    }

    func testWriteRouteCallsHookOnceAndNilHookDoesNothing() {
        let info = RouteInfo(project: "shop", path: "/work/shop", how: "said")
        let saved = Router.onRouteWritten
        defer { Router.onRouteWritten = saved }
        Router.onRouteWritten = nil
        Router.writeRoute(info, to: folder)
        XCTAssertNil(SessionWake.readWake(folder))
        var calls = 0
        Router.onRouteWritten = { _, _ in calls += 1 }
        Router.writeRoute(info, to: folder)
        XCTAssertEqual(calls, 1)
    }
}
