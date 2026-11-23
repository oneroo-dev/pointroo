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
}
