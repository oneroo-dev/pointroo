import Foundation

/// Plain socket helpers shared by the listener (in the app) and the bridge (`Pointroo --mcp`).
enum SocketIO {
    /// Writes every byte, or returns false when the other side is gone.
    static func writeAll(_ descriptor: Int32, _ text: String) -> Bool {
        let bytes = Array(text.utf8)
        var offset = 0
        while offset < bytes.count {
            let written = bytes[offset...].withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
            if written < 0 {
                if errno == EINTR { continue }
                return false
            }
            offset += written
        }
        return true
    }

    /// False once the other side has closed. Peeks one byte without taking it.
    static func isOpen(_ descriptor: Int32) -> Bool {
        var byte: UInt8 = 0
        let count = recv(descriptor, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        if count > 0 { return true }
        if count == 0 { return false }
        return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR
    }

    static func loopbackAddress(port: UInt16) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        return address
    }
}

/// Reads newline-terminated lines from a socket.
struct LineReader {
    let descriptor: Int32
    private var buffer: [UInt8] = []

    init(descriptor: Int32) { self.descriptor = descriptor }

    /// The next line, or nil on end of input, an error, a line over 16 MB, or when nothing arrives within the timeout (-1 waits forever).
    mutating func readLine(timeoutMillis: Int32 = -1) -> String? {
        while true {
            if let newline = buffer.firstIndex(of: 10) {
                var text = String(decoding: buffer[..<newline], as: UTF8.self)
                buffer.removeSubrange(...newline)
                if text.hasSuffix("\r") { text.removeLast() }
                return text
            }
            if buffer.count > 16_000_000 { return nil }
            var watched = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&watched, 1, timeoutMillis)
            if ready == 0 { return nil }
            if ready < 0 {
                if errno == EINTR { continue }
                return nil
            }
            var chunk = [UInt8](repeating: 0, count: 65536)
            let count = read(descriptor, &chunk, chunk.count)
            if count <= 0 { return nil }
            buffer.append(contentsOf: chunk[0..<count])
        }
    }
}

/// The MCP server inside the app: every `Pointroo --mcp` bridge connects here over 127.0.0.1, so all agent sessions share one server.
/// One thread accepts, one thread serves each connection (a waiting wait_for_next blocks only its own thread).
enum MCPListener {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var listenDescriptor: Int32 = -1
    nonisolated(unsafe) private static var generation = 0
    nonisolated(unsafe) private static var boundPortValue: UInt16 = 0
    nonisolated(unsafe) private static var statusText = "Shared MCP server: not started"

    /// The port from `defaults write dev.oneroodev.pointroo mcpPort <n>` when it is in 6740...6759, else 6742.
    static var mcpPort: UInt16 {
        let saved = UserDefaults.standard.integer(forKey: "mcpPort")
        return UInt16(MCPPort.normalized(saved))
    }

    /// One plain line for Settings.
    static var status: String { lock.lock(); defer { lock.unlock() }; return statusText }

    /// The port the listener really got (differs from the asked one only when 0 was asked, in tests).
    static var boundPort: UInt16 { lock.lock(); defer { lock.unlock() }; return boundPortValue }

    /// The random token the app writes at start; only a bridge that can read this file (same user) may connect.
    static var tokenFile: URL { Paths.support.appendingPathComponent("mcp-token") }

    static func busyMessage(port: UInt16) -> String {
        "Port \(port) is in use by another program. Quit it, or pick another port: defaults write dev.oneroodev.pointroo mcpPort <n>, then restart Pointroo."
    }

    /// Called once at launch: a busy port becomes a toast (and shows in Settings), never a crash.
    /// `moved` is told the busy port and the one now used when the listener moved to another port.
    @MainActor static func startAtLaunch(toast: @escaping @MainActor (String?) -> Void,
                                         moved: @escaping @MainActor (Int, Int) -> Void = { _, _ in }) {
        let port = mcpPort
        guard start(port: port) != nil else { return }
        // Busy at launch: try the next free port once (it is saved and the agent install runs again). Only a failure shows.
        DispatchQueue.global(qos: .utility).async {
            switch MCPPort.useAnother(current: Int(port)) {
            case .success(let other):
                NSLog("pointroo: port \(port) was busy, now using \(other)")
                DispatchQueue.main.async { MainActor.assumeIsolated { moved(Int(port), other) } }
            case .failure(let error):
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        toast(error.message)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { MainActor.assumeIsolated { toast(nil) } }
                    }
                }
            }
        }
    }

    /// Binds 127.0.0.1:port and starts accepting. Returns nil on success, else a plain message.
    static func start(port requested: UInt16) -> String? {
        stop()
        signal(SIGPIPE, SIG_IGN)
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return fail("The shared MCP server could not open a network socket (error \(errno)).") }
        var yes: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var address = SocketIO.loopbackAddress(port: requested)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else {
            let code = errno
            close(descriptor)
            return fail(code == EADDRINUSE ? busyMessage(port: requested) : "The shared MCP server could not use port \(requested) (error \(code)).")
        }
        guard listen(descriptor, 32) == 0 else {
            close(descriptor)
            return fail("The shared MCP server could not listen on port \(requested) (error \(errno)).")
        }
        var actual = SocketIO.loopbackAddress(port: 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) } }
        let port = UInt16(bigEndian: actual.sin_port)
        guard let token = writeToken() else {
            close(descriptor)
            return fail("The shared MCP server could not write its token file \(tokenFile.path).")
        }
        lock.lock()
        generation += 1
        let mine = generation
        listenDescriptor = descriptor
        boundPortValue = port
        statusText = "Shared MCP server: running on 127.0.0.1:\(port)"
        lock.unlock()
        let thread = Thread { acceptLoop(descriptor: descriptor, generation: mine, token: token) }
        thread.name = "pointroo-mcp-accept"
        thread.start()
        return nil
    }

    /// Stops accepting. Connections that are already open stay until their client leaves.
    static func stop() {
        lock.lock()
        generation += 1
        let descriptor = listenDescriptor
        listenDescriptor = -1
        boundPortValue = 0
        lock.unlock()
        if descriptor >= 0 { close(descriptor) }
    }

    private static func fail(_ message: String) -> String {
        lock.lock(); statusText = message; lock.unlock()
        return message
    }

    private static func isCurrent(_ mine: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return generation == mine }

    private static func writeToken() -> String? {
        let token = (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = open(tokenFile.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard file >= 0 else { return nil }
        defer { close(file) }
        fchmod(file, 0o600)
        return SocketIO.writeAll(file, token + "\n") ? token : nil
    }

    private static func acceptLoop(descriptor: Int32, generation mine: Int, token: String) {
        while isCurrent(mine) {
            var watched = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&watched, 1, 500)
            if ready <= 0 || !isCurrent(mine) { continue }
            let client = accept(descriptor, nil, nil)
            if client < 0 { continue }
            var yes: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
            let thread = Thread { serve(client, token: token) }
            thread.name = "pointroo-mcp-connection"
            thread.start()
        }
    }

    /// One bridge: a hello with the right token first (anything else is closed at once), an ack, then lines both ways.
    private static func serve(_ descriptor: Int32, token: String) {
        defer { close(descriptor) }
        var reader = LineReader(descriptor: descriptor)
        guard let first = reader.readLine(timeoutMillis: 2000), let hello = MCPBridge.parseHello(first, token: token) else { return }
        guard SocketIO.writeAll(descriptor, "{\"pointroo_ack\":1}\n") else { return }
        let connection = MCPConnection(cwd: hello.cwd, startedAt: hello.started, manageLiveSession: false, livePid: hello.pid,
                                       isOpen: { SocketIO.isOpen(descriptor) })
        while let line = reader.readLine() {
            guard let reply = connection.handle(line: line) else { continue }
            if !SocketIO.writeAll(descriptor, reply + "\n") { return }
        }
    }
}
