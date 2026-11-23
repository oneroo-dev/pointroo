import Foundation

/// `Pointroo --mcp`: forwards the agent's stdio lines to the shared server in the app and the replies back.
/// When the app is not running (or does not answer the hello) it serves in this process, as it did before.
/// This process, not the app, is the live session: it writes `live/<pid>.json` and keeps it fresh.
enum MCPBridge {
    struct Hello: Equatable {
        var cwd: String
        var pid: Int32
        var started: Date
        var token: String
    }

    static func helloLine(cwd: String, pid: Int32, started: Date, token: String) -> String {
        let object: [String: Any] = ["pointroo_hello": 1, "cwd": cwd, "pid": Int(pid), "started": timestamp(started), "token": token]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The hello, or nil when the line is not a hello or carries the wrong token.
    static func parseHello(_ line: String, token: String) -> Hello? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              (object["pointroo_hello"] as? Int) == 1,
              let cwd = object["cwd"] as? String, !cwd.isEmpty,
              let pid = object["pid"] as? Int,
              let startedText = object["started"] as? String, let started = parseTimestamp(startedText),
              let given = object["token"] as? String, !token.isEmpty, given == token else { return nil }
        return Hello(cwd: cwd, pid: Int32(truncatingIfNeeded: pid), started: started, token: given)
    }

    /// The client name inside an `initialize` request line, or nil for any other line.
    static func clientName(fromInitialize line: String) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              object["method"] as? String == "initialize", object["id"] != nil else { return nil }
        let info = (object["params"] as? [String: Any])?["clientInfo"] as? [String: Any]
        guard let name = info?["name"] as? String, !name.isEmpty else { return nil }
        return name
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func parseTimestamp(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    /// Connects to the app and completes the hello and ack. Nil when nothing listens or the ack does not come in time.
    static func connect(port: UInt16, token: String, cwd: String, started: Date, ackTimeoutMillis: Int32 = 1000) -> Int32? {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        var yes: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = SocketIO.loopbackAddress(port: port)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0,
              SocketIO.writeAll(descriptor, helloLine(cwd: cwd, pid: getpid(), started: started, token: token) + "\n") else {
            close(descriptor)
            return nil
        }
        var reader = LineReader(descriptor: descriptor)
        guard let answer = reader.readLine(timeoutMillis: ackTimeoutMillis),
              let object = (try? JSONSerialization.jsonObject(with: Data(answer.utf8))) as? [String: Any],
              (object["pointroo_ack"] as? Int) == 1 else {
            close(descriptor)
            return nil
        }
        return descriptor
    }

    static func readToken() -> String {
        ((try? String(contentsOf: MCPListener.tokenFile, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func run() {
        setvbuf(stdout, nil, _IOLBF, 0)
        signal(SIGPIPE, SIG_IGN)
        let session = BridgeSession(cwd: FileManager.default.currentDirectoryPath, started: Date(),
                                    token: readToken(), port: MCPListener.mcpPort)
        guard session.connectFirst() else {
            MCPServer.run()
            return
        }
        session.run()
    }
}

/// The state of one bridge process. Requests already sent are never sent again (nothing is taken twice);
/// requests not yet sent wait for a reconnect.
final class BridgeSession {
    private let cwd: String
    private let started: Date
    private let token: String
    private let port: UInt16
    private let lock = NSLock()
    private let outputLock = NSLock()
    private var descriptor: Int32 = -1
    private var generation = 0
    private var pending: [String: (id: Any, method: String)] = [:]
    private var swallow: Set<String> = []
    private var initializeLine: String?
    private var local: MCPConnection?

    init(cwd: String, started: Date, token: String, port: UInt16) {
        self.cwd = cwd
        self.started = started
        self.token = token
        self.port = port
    }

    func connectFirst() -> Bool {
        guard let first = MCPBridge.connect(port: port, token: token, cwd: cwd, started: started) else { return false }
        attach(first)
        return true
    }

    func run() {
        let keepAlive = Thread {
            while true {
                Thread.sleep(forTimeInterval: 15)
                LiveSessions.touch()
            }
        }
        keepAlive.name = "pointroo-mcp-keepalive"
        keepAlive.start()
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }
            if let name = MCPBridge.clientName(fromInitialize: line) {
                initializeLine = line
                LiveSessions.register(cwd: cwd, agent: name)
            } else {
                LiveSessions.touch()
            }
            forward(line)
        }
        lock.lock()
        let current = descriptor
        descriptor = -1
        lock.unlock()
        if current >= 0 { close(current) }
        LiveSessions.unregister()
    }

    private static func key(for id: Any) -> String {
        if let text = id as? String { return "s:" + text }
        return "n:\(id)"
    }

    private func parse(_ line: String) -> (id: Any, method: String)? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], let id = object["id"],
              let method = object["method"] as? String else { return nil }
        return (id, method)
    }

    private func write(_ text: String) {
        outputLock.lock()
        print(text)
        fflush(stdout)
        outputLock.unlock()
    }

    private func attach(_ newDescriptor: Int32) {
        lock.lock()
        descriptor = newDescriptor
        generation += 1
        let mine = generation
        lock.unlock()
        let thread = Thread { [self] in
            var reader = LineReader(descriptor: newDescriptor)
            while let line = reader.readLine() { received(line) }
            dropped(newDescriptor, generation: mine)
        }
        thread.name = "pointroo-mcp-bridge-reader"
        thread.start()
    }

    private func received(_ line: String) {
        if let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], let id = object["id"] {
            let key = Self.key(for: id)
            lock.lock()
            let swallowed = swallow.remove(key) != nil
            pending.removeValue(forKey: key)
            lock.unlock()
            if swallowed { return }
        }
        write(line)
    }

    /// The app went away: every request that was already sent gets an error reply (never a resend).
    private func dropped(_ closed: Int32, generation mine: Int) {
        lock.lock()
        guard generation == mine, descriptor == closed else { lock.unlock(); return }
        descriptor = -1
        let waiting = pending
        pending = [:]
        swallow = []
        lock.unlock()
        close(closed)
        for (_, request) in waiting { write(Self.restartedReply(id: request.id, method: request.method)) }
    }

    static func restartedReply(id: Any, method: String) -> String {
        let message = "Pointroo restarted; call the tool again"
        let object: [String: Any]
        if method == "tools/call" {
            object = ["jsonrpc": "2.0", "id": id, "result": ["content": [["type": "text", "text": message]], "isError": true]]
        } else {
            object = ["jsonrpc": "2.0", "id": id, "error": ["code": -32000, "message": message]]
        }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func forward(_ line: String) {
        let request = parse(line)
        if local != nil {
            if reconnect(seconds: 0) { local = nil } else { handleLocally(line); return }
        }
        while true {
            lock.lock()
            let current = descriptor
            if current >= 0, let request { pending[Self.key(for: request.id)] = request }
            lock.unlock()
            if current >= 0 {
                if SocketIO.writeAll(current, line + "\n") { return }
                if let request {
                    lock.lock()
                    let stillMine = pending.removeValue(forKey: Self.key(for: request.id)) != nil
                    lock.unlock()
                    // The reader already answered it with the restart error: it counts as sent.
                    if !stillMine { return }
                }
                dropped(current, generation: generationOf(current))
            }
            if !reconnect(seconds: 10) {
                startLocal()
                handleLocally(line)
                return
            }
        }
    }

    private func generationOf(_ current: Int32) -> Int {
        lock.lock(); defer { lock.unlock() }
        return descriptor == current ? generation : -1
    }

    /// Tries to reach the app again for up to `seconds`; on success replays the cached initialize and swallows its reply.
    private func reconnect(seconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if let fresh = MCPBridge.connect(port: port, token: MCPBridge.readToken(), cwd: cwd, started: started) {
                if let initialize = initializeLine, let request = parse(initialize) {
                    lock.lock()
                    swallow.insert(Self.key(for: request.id))
                    lock.unlock()
                    attach(fresh)
                    _ = SocketIO.writeAll(fresh, initialize + "\n")
                } else {
                    attach(fresh)
                }
                return true
            }
            if seconds > 0 { Thread.sleep(forTimeInterval: 0.5) }
        } while Date() < deadline
        return false
    }

    private func startLocal() {
        let connection = MCPConnection(cwd: cwd, startedAt: started, manageLiveSession: false, livePid: getpid())
        if let initialize = initializeLine { _ = connection.handle(line: initialize) }
        local = connection
    }

    private func handleLocally(_ line: String) {
        if let reply = local?.handle(line: line) { write(reply) }
    }
}
