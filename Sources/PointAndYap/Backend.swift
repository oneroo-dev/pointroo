import Foundation

/// R5: the backend the new screens need. Pure logic lives here so tests can reach it without the app running.

/// The ports the MCP server may use. Pointroo stays inside its family range, and 6742 is the default.
enum MCPPort {
    static let range: ClosedRange<Int> = 6740...6759
    static let defaultPort = 6742

    /// The first port after `current` (wrapping round inside `allowed`) that is not busy. Nil when every other port is busy.
    /// `isBusy` is passed in so tests do not need real sockets.
    static func nextFree(after current: Int, in allowed: ClosedRange<Int> = range, isBusy: (Int) -> Bool) -> Int? {
        let count = allowed.count
        let startOffset = allowed.contains(current) ? current - allowed.lowerBound : -1
        for step in 1...count {
            let port = allowed.lowerBound + (startOffset + step) % count
            if port != current, !isBusy(port) { return port }
        }
        return nil
    }

    /// A port from the saved setting, only when it is inside the range; else the default.
    static func normalized(_ value: Int) -> Int { range.contains(value) ? value : defaultPort }

    /// True when this port on 127.0.0.1 cannot be bound (something else holds it).
    static func isBusyOnLoopback(_ port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return true }
        defer { close(descriptor) }
        var address = SocketIO.loopbackAddress(port: UInt16(port))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        return bound != 0
    }

    /// "Use another port": picks the next free port, saves it as `mcpPort`, restarts the listener and runs the agent install
    /// again. Returns the new port, or a plain message when nothing could be done.
    static func useAnother(isBusy: (Int) -> Bool = isBusyOnLoopback,
                           restart: (UInt16) -> String? = { MCPListener.start(port: $0) },
                           install: () -> Void = { AgentInstall.run() },
                           save: (Int) -> Void = { UserDefaults.standard.set($0, forKey: "mcpPort") },
                           current: Int = Int(MCPListener.mcpPort)) -> Result<Int, BackendError> {
        guard let port = nextFree(after: current, isBusy: isBusy) else {
            return .failure(BackendError("No free port between \(range.lowerBound) and \(range.upperBound)."))
        }
        save(port)
        if let message = restart(UInt16(port)) { return .failure(BackendError(message)) }
        install()
        return .success(port)
    }
}

struct BackendError: Error, Equatable {
    var message: String
    init(_ message: String) { self.message = message }
}

/// A practice recording (the first-run "Try it" card): a flag file in the session folder. Its item is done by "you"
/// at once, so no agent is ever handed it.
enum Practice {
    static let flagName = "practice"
    static let agent = "you"

    static func flagURL(_ directory: URL) -> URL { directory.appendingPathComponent(flagName) }
    static func isPractice(_ directory: URL) -> Bool { FileManager.default.fileExists(atPath: flagURL(directory).path) }

    static func mark(_ directory: URL) {
        try? Data().write(to: flagURL(directory))
    }
}

/// `pointroo://item/<id>`, where the id is "<session>#<n>" (the # may also come as %23).
enum DeepLink {
    static let scheme = "pointroo"

    /// The item id in a link, or nil when it is not an item link or the id is not safe (empty, "/", "\", or "..").
    static func itemID(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "item" else { return nil }
        var id = url.path
        if id.hasPrefix("/") { id.removeFirst() }
        if let fragment = url.fragment, !fragment.isEmpty { id += "#" + fragment }
        return isValid(id) ? id : nil
    }

    /// The same rules Items.set applies to the session part, plus: the part after "#" (if any) is a number.
    static func isValid(_ id: String) -> Bool {
        guard !id.isEmpty, !id.contains("/"), !id.contains("\\"), !id.contains("..") else { return false }
        let parts = id.split(separator: "#", omittingEmptySubsequences: false).map(String.init)
        guard parts.count <= 2, !parts[0].isEmpty else { return false }
        if parts.count == 2 { return !parts[1].isEmpty && parts[1].allSatisfy(\.isNumber) }
        return true
    }
}

extension Items {
    enum RerouteResult: Equatable {
        case moved
        case missing
        case done
        case saveFailed
    }

    /// Moves an item to another project: writes route.json of its session as picked, and teaches the router like a picker pick.
    /// A done item is refused.
    @discardableResult
    static func reroute(id: String, to project: Project) -> RerouteResult {
        guard DeepLink.isValid(id), let session = id.split(separator: "#").first.map(String.init) else { return .missing }
        return locked {
            let directory = Paths.root.appendingPathComponent(session)
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("session.md").path),
                  let item = items(in: directory, state: readState(directory)).items.first(where: { $0.id == id }) else { return .missing }
            if item.status == "done" { return .done }
            let info = RouteInfo(project: project.name, path: project.path, how: "picked")
            Router.writeRoute(info, to: directory)
            guard Router.readRoute(directory) == info else { return .saveFailed }
            Projects.learn(from: directory, project: project)
            return .moved
        }
    }
}
