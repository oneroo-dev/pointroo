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

    func testSafeSocketRejectsBadPaths() throws {
        let directory = "/tmp/pr-wake-dir-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        cleanupPaths.append(directory)
        let prefixes = [directory + "/"]

        XCTAssertFalse(SessionWake.safeSocket("/var/tmp/other.sock"))
        XCTAssertFalse(SessionWake.safeSocket("/tmp/cc-socks/../etc/passwd"))

        let plainFile = directory + "/plain.sock"
        FileManager.default.createFile(atPath: plainFile, contents: Data())
        XCTAssertFalse(SessionWake.safeSocket(plainFile, allowedPrefixes: prefixes))

        let link = directory + "/link.sock"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: plainFile)
        XCTAssertFalse(SessionWake.safeSocket(link, allowedPrefixes: prefixes))
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
                bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
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
}
