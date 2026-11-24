import Foundation

/// The ids of done items the user has seen, kept in `notices-seen.json` in the app support folder (next to the queue).
/// The file is a JSON list, oldest first, and holds at most the newest `limit` ids.
struct NoticeStore {
    static let limit = 500

    var folder: URL

    init(folder: URL? = nil) {
        self.folder = folder ?? Paths.support
    }

    var file: URL { folder.appendingPathComponent("notices-seen.json") }

    /// The seen ids, oldest first. An empty list when the file is missing or broken.
    func seenIds() -> [String] {
        guard let data = try? Data(contentsOf: file),
              let list = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return list
    }

    /// Adds ids that are not in the list yet, keeps the newest `limit`, and saves under the queue lock. False when it could not save.
    @discardableResult
    func markSeen(_ ids: [String]) -> Bool {
        Items.locked {
            var list = seenIds()
            var known = Set(list)
            for id in ids where !known.contains(id) {
                list.append(id)
                known.insert(id)
            }
            if list.count > Self.limit { list = Array(list.suffix(Self.limit)) }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try JSONEncoder.pretty.encode(list).write(to: file, options: .atomic)
                return true
            } catch {
                return false
            }
        }
    }
}

/// Which items and questions are notices right now. Pure: data in, answer out.
enum Notices {
    /// A done item the user has not seen, marked done by an agent (not by "you" and not by the user's own Done button).
    static func isUnseenDone(_ item: Item, seen: Set<String>) -> Bool {
        guard item.status == "done", let by = item.by, !by.isEmpty, by != "you", by != "user" else { return false }
        return !seen.contains(item.id)
    }

    /// The ids of every notice, like "done:<item id>" and "question:<question id>", sorted.
    static func identifiers(items: [Item], questions: [Question], seen: Set<String>) -> [String] {
        let done = items.filter { isUnseenDone($0, seen: seen) }.map { "done:\($0.id)" }
        let asked = questions.map { "question:\($0.id)" }
        return (done + asked).sorted()
    }
}
