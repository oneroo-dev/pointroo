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
    var cwd: String? = nil
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

    // True for a folder named cc-socks or cc-socks-<digits>.
    static func isSocketFolderName(_ name: String) -> Bool {
        name.range(of: "^cc-socks(-[0-9]+)?$", options: .regularExpression) != nil
    }

    // A Claude socket is safe when: no "..", the file is a real socket (not a link) owned by us, and its folder is
    // named cc-socks or cc-socks-<digits>, is a real folder owned by us, with no group or other permission bits.
    static func safeSocket(_ path: String, owner: uid_t = getuid()) -> Bool {
        guard !path.contains("..") else { return false }
        let parent = (path as NSString).deletingLastPathComponent
        guard isSocketFolderName((parent as NSString).lastPathComponent) else { return false }
        var folderInfo = stat()
        guard lstat(parent, &folderInfo) == 0 else { return false }
        guard (folderInfo.st_mode & S_IFMT) == S_IFDIR else { return false }
        guard folderInfo.st_uid == owner else { return false }
        guard (folderInfo.st_mode & 0o077) == 0 else { return false }
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        guard (info.st_mode & S_IFMT) == S_IFSOCK else { return false }
        return info.st_uid == owner
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

// What was done for one recording, saved as wake.json in the recording folder.
struct WakeRecord: Codable, Equatable {
    var project: String
    var target: String?
    var name: String?
    var pid: Int?
    var at: Date
    var result: String
}

extension SessionWake {
    static func wakeURL(_ directory: URL) -> URL { directory.appendingPathComponent("wake.json") }

    static func readWake(_ directory: URL) -> WakeRecord? {
        (try? Data(contentsOf: wakeURL(directory))).flatMap { try? JSONDecoder.iso.decode(WakeRecord.self, from: $0) }
    }

    // owners.json in the support folder: project name -> hostSessionId or sessionId. Missing file = empty.
    static func loadOwners(from file: URL = Paths.support.appendingPathComponent("owners.json")) -> [String: String] {
        guard let data = try? Data(contentsOf: file),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        var result: [String: String] = [:]
        for (name, target) in map { result[name.lowercased()] = target }
        return result
    }

    static func wakeText(folder: String, project: String) -> String {
        "New Pointroo recording \(folder) for \(project). Call get_open_items with scope \"all\" (pointroo MCP), "
            + "take the item(s) for \(project), do them, mark_done with the fix commit in the note. "
            + "release_items anything that is not yours."
    }

    // True when the first entry wins over the second: desktop, then idle, then the higher pid.
    private static func ranksHigher(_ first: ClaudeSessionEntry, _ second: ClaudeSessionEntry) -> Bool {
        let firstDesktop = first.hostSessionId != nil
        let secondDesktop = second.hostSessionId != nil
        if firstDesktop != secondDesktop { return firstDesktop }
        let firstIdle = first.status == "idle"
        let secondIdle = second.status == "idle"
        if firstIdle != secondIdle { return firstIdle }
        return first.pid > second.pid
    }

    private static func best(_ candidates: [ClaudeSessionEntry]) -> ClaudeSessionEntry? {
        candidates.sorted(by: ranksHigher).first
    }

    // Who owns a project: owners.json, then a session named like the project or an alias (ignoring case),
    // then a session whose cwd is the project path, else the deepest one inside it.
    static func owner(for project: String, path: String, entries: [ClaudeSessionEntry],
                      owners: [String: String], aliases: [String] = [],
                      socketCheck: (String) -> Bool = { SessionWake.safeSocket($0) }) -> ClaudeSessionEntry? {
        let usable = entries.filter { entry in
            guard let socketPath = entry.messagingSocketPath else { return false }
            return socketCheck(socketPath)
        }
        if let target = owners[project.lowercased()] {
            let matches = usable.filter { $0.hostSessionId == target || $0.sessionId == target }
            if let found = best(matches) { return found }
        }
        let names = ([project] + aliases).map { $0.lowercased() }
        let named = usable.filter { entry in
            guard let name = entry.name?.lowercased() else { return false }
            return names.contains(name)
        }
        if let found = best(named) { return found }
        let projectPath = Router.canonical(path)
        let exact = usable.filter { entry in entry.cwd.map { Router.canonical($0) == projectPath } ?? false }
        if let found = best(exact) { return found }
        let inside = usable.filter { entry in entry.cwd.map { Router.canonical($0).hasPrefix(projectPath + "/") } ?? false }
        let depths = inside.map { Router.canonical($0.cwd ?? "").count }
        guard let deepest = depths.max() else { return nil }
        return best(inside.filter { Router.canonical($0.cwd ?? "").count == deepest })
    }

    // Wakes the session that owns the routed project and writes wake.json. Returns the result text, or nil when
    // nothing was done (switch off, or the same project was already handled). Every input can be injected for tests.
    @discardableResult
    static func wakeForRoute(_ info: RouteInfo, directory: URL,
                             enabled: Bool = (UserDefaults.standard.object(forKey: "wakeSessions") as? Bool) ?? true,
                             entries: [ClaudeSessionEntry]? = nil,
                             owners: [String: String]? = nil,
                             projects: [Project]? = nil,
                             listening: [LiveSession]? = nil,
                             socketCheck: (String) -> Bool = { SessionWake.safeSocket($0) },
                             sender: (Data, String) throws -> Void = { try SessionWake.send($0, to: $1) },
                             now: Date = Date(),
                             log: (String) -> Void = { NSLog("pointroo: \($0)") }) -> String? {
        guard enabled else { return nil }
        if readWake(directory)?.project == info.project { return nil }
        let folderName = directory.lastPathComponent

        func record(_ target: String?, _ entry: ClaudeSessionEntry?, _ result: String) -> String {
            writeLogged(WakeRecord(project: info.project, target: target, name: entry?.name,
                                   pid: entry?.pid, at: now, result: result), to: wakeURL(directory))
            log("wake \(folderName) for \(info.project): \(result)")
            return result
        }

        let listeners = listening ?? LiveSessions.listening()
        if listeners.contains(where: { Router.samePath($0.cwd, info.path) }) { return record(nil, nil, "listening") }

        let knownProjects = projects ?? Projects.known()
        let matched = knownProjects.first { Router.samePath($0.path, info.path) || $0.name.lowercased() == info.project.lowercased() }
        let sessionEntries = entries ?? Self.entries(in: defaultFolder)
        let found = owner(for: info.project, path: info.path, entries: sessionEntries, owners: owners ?? loadOwners(),
                          aliases: matched?.aliases ?? [], socketCheck: socketCheck)
        guard let entry = found, let socketPath = entry.messagingSocketPath else {
            // An old Claude Code writes registry files without a socket path: it cannot be woken.
            if !sessionEntries.isEmpty, sessionEntries.allSatisfy({ $0.messagingSocketPath == nil }) {
                return record(nil, nil, "claude code too old for wake (needs 2.1.224+)")
            }
            return record(nil, nil, "no owner")
        }
        let target = entry.hostSessionId ?? entry.sessionId
        do {
            let data = try frame(text: wakeText(folder: folderName, project: info.project), sessionId: entry.sessionId)
            try sender(data, socketPath)
            return record(target, entry, "sent")
        } catch {
            return record(target, entry, "failed: \(error)")
        }
    }
}
