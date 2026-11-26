import Foundation

// One open Claude session, from its registry file in ~/.claude/sessions.
// Only the fields we need; other fields in the file are ignored.
struct ClaudeSessionEntry: Decodable, Equatable {
    var pid: Int
    var sessionId: String
    var hostSessionId: String?
    var name: String?
    var messagingSocketPath: String?
    var status: String?
}

enum SessionWake {
    enum WakeError: Error, CustomStringConvertible {
        case emptyText
        case encodeFailed
        case pathTooLong(String)
        case socketFailed(String)
        case connectFailed(String)
        case writeFailed(String)

        var description: String {
            switch self {
            case .emptyText: return "the text is empty"
            case .encodeFailed: return "could not build the message"
            case .pathTooLong(let path): return "socket path is too long: \(path)"
            case .socketFailed(let reason): return "could not create socket: \(reason)"
            case .connectFailed(let reason): return "could not connect: \(reason)"
            case .writeFailed(let reason): return "could not write: \(reason)"
            }
        }
    }

    static let allowedPrefixes = ["/tmp/cc-socks/", "/tmp/cc-socks-"]

    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions")
    }

    // Reads only files named <digits>.json. Never opens the .key files.
    static func entries(in folder: URL) -> [ClaudeSessionEntry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return []
        }
        var result: [ClaudeSessionEntry] = []
        for name in names.sorted() {
            guard name.range(of: "^[0-9]+\\.json$", options: .regularExpression) != nil else { continue }
            let url = folder.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let entry = try? JSONDecoder().decode(ClaudeSessionEntry.self, from: data) else { continue }
            result.append(entry)
        }
        return result
    }

    // Match by hostSessionId or sessionId. With several matches, prefer the
    // newest pid whose socket exists.
    static func find(_ target: String, in entries: [ClaudeSessionEntry]) -> ClaudeSessionEntry? {
        let matches = entries.filter { $0.hostSessionId == target || $0.sessionId == target }
        let sorted = matches.sorted { $0.pid > $1.pid }
        let withSocket = sorted.first { entry in
            guard let path = entry.messagingSocketPath else { return false }
            return FileManager.default.fileExists(atPath: path)
        }
        return withSocket ?? sorted.first
    }

    static func frame(text: String, sessionId: String, messageId: String? = nil) throws -> Data {
        guard !text.isEmpty else { throw WakeError.emptyText }
        let escapedText = text.replacingOccurrences(
            of: "</cross-session-message", with: "<\\/cross-session-message")
        let wrapped = "<cross-session-message from-name=\"Pointroo\">\n" + escapedText
            + "\n</cross-session-message>"
        let object: [String: Any] = [
            "msgV": 1,
            "msg_id": messageId ?? UUID().uuidString.lowercased(),
            "type": "user",
            "message": ["role": "user", "content": wrapped],
            "priority": "next",
            "session_id": sessionId,
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            throw WakeError.encodeFailed
        }
        data.append(0x0A)
        return data
    }

    static func safeSocket(_ path: String, allowedPrefixes: [String] = SessionWake.allowedPrefixes) -> Bool {
        guard !path.contains("..") else { return false }
        guard allowedPrefixes.contains(where: { path.hasPrefix($0) }) else { return false }
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        guard (info.st_mode & S_IFMT) == S_IFSOCK else { return false }
        return info.st_uid == getuid()
    }

    static func send(_ data: Data, to path: String) throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw WakeError.socketFailed(String(cString: strerror(errno))) }
        defer { close(descriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < capacity else { throw WakeError.pathTooLong(path) }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: UInt8.self, capacity: capacity) { bytes in
                for (offset, byte) in pathBytes.enumerated() { bytes[offset] = byte }
                bytes[pathBytes.count] = 0
            }
        }

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        // A closed peer must give an error, not kill the process with SIGPIPE.
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { throw WakeError.connectFailed(String(cString: strerror(errno))) }

        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var written = 0
            while written < buffer.count {
                let count = write(descriptor, base + written, buffer.count - written)
                if count < 0 {
                    if errno == EINTR { continue }
                    throw WakeError.writeFailed(String(cString: strerror(errno)))
                }
                written += count
            }
        }
        shutdown(descriptor, SHUT_WR)
    }

    // args[index] is "--wake"; the target and the text follow it.
    static func run(_ args: [String], from index: Int, folder: URL = SessionWake.defaultFolder) -> Int32 {
        let rest = Array(args.dropFirst(index + 1))
        guard let target = rest.first else {
            print("failed: usage: --wake <local_id or session id> \"text\"")
            return 1
        }
        let text = rest.dropFirst().joined(separator: " ")
        guard let entry = find(target, in: entries(in: folder)) else {
            print("not found \(target)")
            return 1
        }
        guard let path = entry.messagingSocketPath, safeSocket(path) else {
            print("unsafe socket \(entry.messagingSocketPath ?? "(none)")")
            return 1
        }
        do {
            let data = try frame(text: text, sessionId: entry.sessionId)
            try send(data, to: path)
            print("sent \(entry.name ?? entry.sessionId) \(entry.pid)")
            return 0
        } catch {
            print("failed: \(error)")
            return 1
        }
    }
}
