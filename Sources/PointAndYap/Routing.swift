import Foundation

/// A project the user works on: its folder, and what points at it (spoken names, hosts, window titles).
struct Project: Codable, Equatable {
    var name: String
    var path: String
    var aliases: [String] = []
    var hosts: [String] = []
    var titles: [String] = []

    init(name: String, path: String, aliases: [String] = [], hosts: [String] = [], titles: [String] = []) {
        self.name = name; self.path = path; self.aliases = aliases; self.hosts = hosts; self.titles = titles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? URL(fileURLWithPath: path).lastPathComponent
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        hosts = try container.decodeIfPresent([String].self, forKey: .hosts) ?? []
        titles = try container.decodeIfPresent([String].self, forKey: .titles) ?? []
    }
}

/// A running agent session: its `Pointroo --mcp` process writes `live/<pid>.json` while it runs.
struct LiveSession: Codable, Equatable {
    var pid: Int32
    var cwd: String
    var agent: String
    var started: Date
    var lastSeen: Date
}

/// Where an item was sent: written to `route.json` in the session folder.
struct RouteInfo: Codable, Equatable {
    var project: String
    var path: String
    var how: String       // said, screen, only, picked
}

enum LiveSessions {
    static var folder: URL { Paths.support.appendingPathComponent("live") }

    static func file(_ pid: Int32) -> URL { folder.appendingPathComponent("\(pid).json") }

    static func register(cwd: String, agent: String, pid: Int32 = getpid()) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date()
        write(LiveSession(pid: pid, cwd: cwd, agent: agent, started: now, lastSeen: now))
    }

    static func touch(pid: Int32 = getpid()) {
        guard var session = read(file(pid)) else { return }
        session.lastSeen = Date()
        write(session)
    }

    static func unregister(pid: Int32 = getpid()) { try? FileManager.default.removeItem(at: file(pid)) }

    /// Sessions whose process is still alive; files of dead processes are deleted.
    static func all() -> [LiveSession] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var sessions: [LiveSession] = []
        for url in urls where url.pathExtension == "json" {
            guard let session = read(url) else { continue }
            if kill(session.pid, 0) != 0 && errno != EPERM {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            sessions.append(session)
        }
        return sessions.sorted { $0.started < $1.started }
    }

    private static func read(_ url: URL) -> LiveSession? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder.iso.decode(LiveSession.self, from: $0) }
    }

    private static func write(_ session: LiveSession) {
        writeLogged(session, to: file(session.pid))
    }
}

enum Projects {
    static var file: URL { Paths.support.appendingPathComponent("projects.json") }

    static func load() -> [Project] {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([Project].self, from: $0) } ?? []
    }

    static func save(_ projects: [Project]) {
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        writeLogged(projects, to: file)
    }

    /// The projects file plus the folders of live sessions (named after the folder), one entry per path.
    static func known(file projects: [Project] = load(), live: [LiveSession] = LiveSessions.all()) -> [Project] {
        var result = projects
        for session in live where !result.contains(where: { Router.samePath($0.path, session.cwd) }) {
            result.append(Project(name: URL(fileURLWithPath: session.cwd).lastPathComponent, path: session.cwd))
        }
        return result
    }

    /// The project's name for an item's path; the folder name when it is not a known project.
    static func name(for path: String) -> String {
        known().first { Router.samePath($0.path, path) }?.name ?? URL(fileURLWithPath: path).lastPathComponent
    }

    /// The live sessions as projects (one per folder), for the picker.
    static func liveProjects() -> [Project] {
        let live = LiveSessions.all()
        let all = known(live: live)
        var seen: [String] = []
        var result: [Project] = []
        for session in live where !seen.contains(where: { Router.samePath($0, session.cwd) }) {
            seen.append(session.cwd)
            if let project = all.first(where: { Router.samePath($0.path, session.cwd) }) { result.append(project) }
        }
        return result
    }

    /// After the user picked a project for a recording: remember its host:port (or window title) for next time.
    static func learn(from directory: URL, project: Project) {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("events.json")),
              let events = try? JSONDecoder.iso.decode(SessionEvents.self, from: data) else { return }
        var projects = load()
        var index = projects.firstIndex { Router.samePath($0.path, project.path) }
        if index == nil {
            projects.append(Project(name: project.name, path: project.path, aliases: project.aliases))
            index = projects.count - 1
        }
        let urls = events.points.compactMap(\.url)
        if urls.isEmpty {
            if let title = events.points.compactMap(\.window).first(where: { !$0.isEmpty }),
               !projects[index!].titles.contains(title) { projects[index!].titles.append(title) }
        } else {
            for host in urls.compactMap({ Router.hostAndPort($0) }) where Router.isDevelopmentHost(host) {
                if !projects[index!].hosts.contains(host) { projects[index!].hosts.append(host) }
            }
        }
        save(projects)
    }
}

enum Router {
    struct Result: Equatable { var path: String; var how: String }

    /// Said name first, then what was on screen, then the only live session.
    static func route(words: [String], points: [PointEvent], projects: [Project], live: [LiveSession] = []) -> Result? {
        if let project = saidProject(words, projects) { return Result(path: project.path, how: "said") }
        if let project = screenProject(points, projects) { return Result(path: project.path, how: "screen") }
        var folders: [String] = []
        for session in live where !folders.contains(where: { samePath($0, session.cwd) }) { folders.append(session.cwd) }
        if folders.count == 1 { return Result(path: folders[0], how: "only") }
        return nil
    }

    /// The project named in the first 1-3 spoken words. Speech often mishears a name ("Pintro", "point roo"), so the words
    /// are compared without spaces or punctuation and a small edit distance is allowed: none below 4 letters, 1 for 4-5,
    /// 2 for 6-7, 3 for 8 or more ("Point true" for "pointroo"). The spoken text may be at most 2 letters shorter than
    /// the name (so "point" alone is not "pointroo"), and at distance 3 the consonants must be the same, doubles merged
    /// ("pointtrue" and "pointroo" are both "pntr"; "pointfix" is "pntfx", "oneroo" is "nr"). The closest project wins; two projects equally close give no match.
    static func saidProject(_ words: [String], _ projects: [Project]) -> Project? {
        let spoken = words.map { compact($0) }.filter { !$0.isEmpty }.prefix(3)
        guard !spoken.isEmpty else { return nil }
        var best: [(project: Project, distance: Int)] = []
        for project in projects {
            var closest: Int?
            for name in [project.name] + project.aliases {
                let target = compact(name)
                guard !target.isEmpty else { continue }
                let allowed = target.count >= 8 ? 3 : target.count >= 6 ? 2 : target.count >= 4 ? 1 : 0
                for count in 1...spoken.count {
                    let heard = spoken.prefix(count).joined()
                    let distance = editDistance(heard, target)
                    if heard.count + 2 < target.count { continue }
                    if distance == 3, consonants(heard) != consonants(target) { continue }
                    if distance <= allowed, distance < (closest ?? Int.max) { closest = distance }
                }
            }
            if let closest { best.append((project, closest)) }
        }
        guard let nearest = best.map(\.distance).min() else { return nil }
        let winners = best.filter { $0.distance == nearest }
        guard winners.count == 1 || Set(winners.map { canonical($0.project.path) }).count == 1 else { return nil }
        return winners[0].project
    }

    /// Lowercase letters and digits only: "Point Roo!" and "point-roo" both become "pointroo".
    static func compact(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// The consonants of a word, a letter repeated in a row kept once: "pointtrue" -> "pntr".
    static func consonants(_ text: String) -> String {
        var out = ""
        for character in text where !"aeiouy".contains(character) && out.last != character { out.append(character) }
        return out
    }

    static func editDistance(_ first: String, _ second: String) -> Int {
        let a = Array(first), b = Array(second)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    static func screenProject(_ points: [PointEvent], _ projects: [Project]) -> Project? {
        var votes: [Int: Int] = [:]
        for point in points {
            for (index, project) in projects.enumerated() where matches(point, project) { votes[index, default: 0] += 1 }
        }
        guard let best = votes.values.max(), votes.values.filter({ $0 == best }).count == 1,
              let winner = votes.first(where: { $0.value == best })?.key else { return nil }
        return projects[winner]
    }

    static func matches(_ point: PointEvent, _ project: Project) -> Bool {
        let nameTokens = tokens(project.name)
        if let url = point.url, let host = hostAndPort(url) {
            let bare = host.split(separator: ":").first.map(String.init) ?? host
            if project.hosts.contains(where: { $0.contains(":") ? $0.lowercased() == host : $0.lowercased() == bare }) { return true }
            if containsWords(tokens(bare), nameTokens) { return true }
        }
        if let window = point.window, !window.isEmpty {
            if containsWords(tokens(window), nameTokens) { return true }
            let lowered = window.lowercased()
            if project.titles.contains(where: { !$0.isEmpty && lowered.contains($0.lowercased()) }) { return true }
        }
        return false
    }

    /// "localhost:3000" or "app.example.com" for a URL; nil when it has no host.
    static func hostAndPort(_ url: String) -> String? {
        let components = URLComponents(string: url).flatMap { $0.host == nil ? URLComponents(string: "https://" + url) : $0 }
        guard let host = components?.host?.lowercased(), !host.isEmpty else { return nil }
        return components?.port.map { "\(host):\($0)" } ?? host
    }

    /// A host that clearly belongs to one dev project: localhost and its numeric forms (with any port), or a name ending
    /// in .test, .local, .localhost or .internal. Public hosts like claude.ai or github.com are never learned, because
    /// every project's owner looks at them.
    static func isDevelopmentHost(_ hostAndPort: String) -> Bool {
        var host = hostAndPort.lowercased()
        if host == "::1" || host.hasPrefix("::1:") || host.hasPrefix("[::1]") { return true }
        if host.filter({ $0 == ":" }).count == 1, let colon = host.firstIndex(of: ":") {
            host = String(host[..<colon])
        }
        if ["localhost", "127.0.0.1", "::1", "0.0.0.0"].contains(host) { return true }
        return [".test", ".local", ".localhost", ".internal"].contains { host.hasSuffix($0) }
    }

    static func samePath(_ first: String, _ second: String) -> Bool { canonical(first) == canonical(second) }

    /// One path is the other, or inside it.
    static func related(_ first: String, _ second: String) -> Bool {
        let a = canonical(first), b = canonical(second)
        return a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/")
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func containsWords(_ haystack: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<start + needle.count]) == needle { return true }
        return false
    }

    static func routeURL(_ directory: URL) -> URL { directory.appendingPathComponent("route.json") }

    static func readRoute(_ directory: URL) -> RouteInfo? {
        (try? Data(contentsOf: routeURL(directory))).flatMap { try? JSONDecoder().decode(RouteInfo.self, from: $0) }
    }

    static func writeRoute(_ info: RouteInfo, to directory: URL) {
        writeLogged(info, to: routeURL(directory))
    }

    /// Routes a processed recording and saves route.json; nothing is written when no project fits. A project the user picked stays.
    static func routeSession(_ directory: URL, events: SessionEvents, words: [Word]) {
        if readRoute(directory)?.how == "picked" { return }
        let live = LiveSessions.all()
        let projects = Projects.known(live: live)
        guard let result = route(words: words.map(\.text), points: events.points, projects: projects, live: live) else { return }
        let name = projects.first { samePath($0.path, result.path) }?.name ?? URL(fileURLWithPath: result.path).lastPathComponent
        writeRoute(RouteInfo(project: name, path: result.path, how: result.how), to: directory)
    }
}

/// Writes JSON atomically; a failure goes to stderr instead of being ignored.
func writeLogged<T: Encodable>(_ value: T, to url: URL) {
    do { try JSONEncoder.pretty.encode(value).write(to: url, options: .atomic) }
    catch { FileHandle.standardError.write(Data("pointroo: could not save \(url.path): \(error.localizedDescription)\n".utf8)) }
}
