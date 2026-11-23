import XCTest
@testable import PointAndYap

/// The shared MCP server: per-connection state, the TCP listener and the stdio bridge.
final class MCPSharedTests: XCTestCase {
    /// The same temporary sessions and support folders as the other tests (Paths reads them once).
    override class func setUp() { _ = PointAndYapTests.root }

    func initializeLine(client: String, id: Int = 1) -> String {
        "{\"jsonrpc\":\"2.0\",\"id\":\(id),\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\",\"clientInfo\":{\"name\":\"\(client)\"}}}"
    }

    func json(_ line: String?) -> [String: Any] {
        guard let line, let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return [:] }
        return object
    }

    func testTwoConnectionsKeepTheirOwnNameFolderAndStart() {
        let early = Date(timeIntervalSinceNow: -100)
        let late = Date(timeIntervalSinceNow: -5)
        let first = MCPConnection(cwd: "/work/alpha", startedAt: early)
        let second = MCPConnection(cwd: "/work/beta", startedAt: late)
        XCTAssertNotNil(first.handle(line: initializeLine(client: "claude-code")))
        XCTAssertNotNil(second.handle(line: initializeLine(client: "codex")))
        XCTAssertEqual(first.agent, "claude-code (alpha)")
        XCTAssertEqual(second.agent, "codex (beta)")
        XCTAssertEqual(first.startedAt, early, "initialize must not reset the start time")
        XCTAssertEqual(second.startedAt, late)
        XCTAssertEqual(first.cwd, "/work/alpha")
    }

    func testNotificationsGetNoReplyAndUnknownMethodsGetAnError() {
        let connection = MCPConnection(cwd: "/work/alpha")
        XCTAssertNil(connection.handle(line: "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"))
        let reply = json(connection.handle(line: "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"nope\"}"))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32601)
        XCTAssertEqual(reply["id"] as? Int, 7)
    }

    func testToolsListFromAConnectionMatchesTheStaticList() {
        let connection = MCPConnection(cwd: "/work/alpha")
        let reply = json(connection.handle(line: "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}"))
        let names = ((reply["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        XCTAssertEqual(names, MCPServer.tools.compactMap { $0["name"] as? String })
    }

    override func tearDown() { MCPListener.stop() }

    /// A socket client like the bridge: connects, sends the hello, waits for the ack.
    final class TestClient {
        let descriptor: Int32
        var reader: LineReader

        init?(port: UInt16, hello: String?) {
            descriptor = socket(AF_INET, SOCK_STREAM, 0)
            reader = LineReader(descriptor: descriptor)
            var address = SocketIO.loopbackAddress(port: port)
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            guard connected == 0 else { return nil }
            if let hello { send(hello) }
        }

        func send(_ line: String) { _ = SocketIO.writeAll(descriptor, line + "\n") }
        func read(timeoutMillis: Int32 = 5000) -> String? { reader.readLine(timeoutMillis: timeoutMillis) }
        func close() { Darwin.close(descriptor) }
    }

    func startListener() throws -> (port: UInt16, token: String) {
        XCTAssertNil(MCPListener.start(port: 0))
        let token = try String(contentsOf: MCPListener.tokenFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        return (MCPListener.boundPort, token)
    }

    func helloLine(cwd: String, token: String, started: Date = Date()) -> String {
        MCPBridge.helloLine(cwd: cwd, pid: getpid(), started: started, token: token)
    }

    func text(of reply: String?) -> String {
        let result = json(reply)["result"] as? [String: Any]
        return (result?["content"] as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined() ?? ""
    }

    func testTheListenerServesTheSameToolsAsStdio() throws {
        let (port, token) = try startListener()
        XCTAssertNotEqual(port, 0)
        XCTAssertTrue(MCPListener.status.contains("\(port)"), MCPListener.status)
        let client = try XCTUnwrap(TestClient(port: port, hello: helloLine(cwd: "/work/n1-tools", token: token)))
        defer { client.close() }
        XCTAssertEqual(client.read(), "{\"pointroo_ack\":1}")
        client.send(initializeLine(client: "claude-code"))
        XCTAssertNotNil(json(client.read())["result"])
        client.send("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}")
        let tools = ((json(client.read())["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        XCTAssertEqual(tools, MCPServer.tools.compactMap { $0["name"] as? String })
    }

    func testABusyPortGivesAMessageWithThePort() throws {
        let occupant = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(occupant) }
        var address = SocketIO.loopbackAddress(port: 0)
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(occupant, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(occupant, 1), 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(occupant, $0, &length) } }
        let busy = UInt16(bigEndian: address.sin_port)
        let message = try XCTUnwrap(MCPListener.start(port: busy))
        XCTAssertTrue(message.contains("\(busy)"), message)
        XCTAssertTrue(message.contains("mcpPort"), message)
        XCTAssertEqual(MCPListener.status, message)
    }

    func testAWrongTokenAndANonHelloAreClosedAtOnce() throws {
        let (port, token) = try startListener()
        let wrong = try XCTUnwrap(TestClient(port: port, hello: helloLine(cwd: "/work/n1-wrong", token: token + "x")))
        XCTAssertNil(wrong.read(), "closed without an ack")
        wrong.close()
        let plain = try XCTUnwrap(TestClient(port: port, hello: "GET / HTTP/1.1"))
        XCTAssertNil(plain.read(), "closed without an answer")
        plain.close()
        let early = try XCTUnwrap(TestClient(port: port, hello: initializeLine(client: "claude-code")))
        XCTAssertNil(early.read(), "a request before the hello is closed")
        early.close()
        let fileToken = try String(contentsOf: MCPListener.tokenFile, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: MCPListener.tokenFile.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertFalse(fileToken.isEmpty)
    }

    func testTwoConnectionsWaitAtTheSameTime() throws {
        let (port, token) = try startListener()
        let first = try XCTUnwrap(TestClient(port: port, hello: helloLine(cwd: "/work/n1-wait-a", token: token)))
        let second = try XCTUnwrap(TestClient(port: port, hello: helloLine(cwd: "/work/n1-wait-b", token: token)))
        defer { first.close(); second.close() }
        XCTAssertNotNil(first.read()); XCTAssertNotNil(second.read())
        let wait = "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"wait_for_next\",\"arguments\":{\"timeout_seconds\":2}}}"
        let began = Date()
        first.send(wait)
        second.send(wait)
        let firstReply = first.read(timeoutMillis: 8000), secondReply = second.read(timeoutMillis: 8000)
        let elapsed = Date().timeIntervalSince(began)
        XCTAssertTrue(text(of: firstReply).hasPrefix("Nothing new yet"), firstReply ?? "nil")
        XCTAssertTrue(text(of: secondReply).hasPrefix("Nothing new yet"), secondReply ?? "nil")
        XCTAssertLessThan(elapsed, 3.5, "both waits run at the same time")
        XCTAssertGreaterThan(elapsed, 1.5)
    }

    func testAClientThatClosesDuringAWaitTakesNothing() throws {
        let (port, token) = try startListener()
        let cwd = "/work/n1-closed"
        let client = try XCTUnwrap(TestClient(port: port, hello: helloLine(cwd: cwd, token: token, started: Date(timeIntervalSinceNow: -60))))
        XCTAssertNotNil(client.read())
        client.send(initializeLine(client: "claude-code"))
        XCTAssertNotNil(client.read())
        client.send("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"wait_for_next\",\"arguments\":{\"timeout_seconds\":6}}}")
        Thread.sleep(forTimeInterval: 0.3)
        client.close()
        let source = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/2026-10-17_120000", withExtension: nil))
        let directory = PointAndYapTests.root.appendingPathComponent("2026-10-17_130001")
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.copyItem(at: source, to: directory)
        let events = try JSONDecoder.iso.decode(SessionEvents.self, from: Data(contentsOf: directory.appendingPathComponent("events.json")))
        let words = try JSONDecoder().decode([Word].self, from: Data(contentsOf: directory.appendingPathComponent("transcript.json")))
        _ = Builder.build(dir: directory, events: events, words: words)
        Router.writeRoute(RouteInfo(project: "n1-closed", path: cwd, how: "said"), to: directory)
        Thread.sleep(forTimeInterval: 2.5)
        let status = Items.items(in: directory, state: Items.readState(directory)).items.first?.status
        XCTAssertEqual(status, "open", "a closed connection must not take the item")
    }

    func testHelloAndInitializeParsing() throws {
        let started = Date(timeIntervalSince1970: 1_700_000_000.25)
        let line = MCPBridge.helloLine(cwd: "/work/alpha", pid: 42, started: started, token: "secret")
        let hello = try XCTUnwrap(MCPBridge.parseHello(line, token: "secret"))
        XCTAssertEqual(hello.cwd, "/work/alpha")
        XCTAssertEqual(hello.pid, 42)
        XCTAssertEqual(hello.started.timeIntervalSince1970, started.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertNil(MCPBridge.parseHello(line, token: "other"))
        XCTAssertNil(MCPBridge.parseHello(line, token: ""))
        XCTAssertNil(MCPBridge.parseHello("not json", token: "secret"))
        XCTAssertNil(MCPBridge.parseHello(initializeLine(client: "x"), token: "secret"))
        XCTAssertEqual(MCPBridge.clientName(fromInitialize: initializeLine(client: "claude-code")), "claude-code")
        XCTAssertNil(MCPBridge.clientName(fromInitialize: "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}"))
        XCTAssertNil(MCPBridge.clientName(fromInitialize: "garbage"))
    }

    func testTheBridgeFallsBackWhenNothingListensOrNobodyAnswers() throws {
        let probe = socket(AF_INET, SOCK_STREAM, 0)
        var address = SocketIO.loopbackAddress(port: 0)
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(probe, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(probe, $0, &length) } }
        let port = UInt16(bigEndian: address.sin_port)
        close(probe)
        XCTAssertNil(MCPBridge.connect(port: port, token: "t", cwd: "/work/alpha", started: Date()), "nothing listens")

        let silent = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(silent) }
        var silentAddress = SocketIO.loopbackAddress(port: 0)
        _ = withUnsafePointer(to: &silentAddress) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(silent, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        listen(silent, 1)
        var silentLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &silentAddress) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(silent, $0, &silentLength) } }
        let silentPort = UInt16(bigEndian: silentAddress.sin_port)
        XCTAssertNil(MCPBridge.connect(port: silentPort, token: "t", cwd: "/work/alpha", started: Date(), ackTimeoutMillis: 200), "no ack in time")
    }

    func testAConnectedBridgeGetsADescriptorFromTheRealListener() throws {
        let (port, token) = try startListener()
        let descriptor = try XCTUnwrap(MCPBridge.connect(port: port, token: token, cwd: "/work/alpha", started: Date()))
        close(descriptor)
        XCTAssertNil(MCPBridge.connect(port: port, token: "wrong", cwd: "/work/alpha", started: Date(), ackTimeoutMillis: 500))
    }

    func testTheRestartReplyIsAnErrorResultForToolCalls() {
        let reply = json(BridgeSession.restartedReply(id: 9, method: "tools/call"))
        XCTAssertEqual(reply["id"] as? Int, 9)
        XCTAssertEqual((reply["result"] as? [String: Any])?["isError"] as? Bool, true)
        XCTAssertNotNil(json(BridgeSession.restartedReply(id: 10, method: "ping"))["error"])
    }
}
