import Foundation

/// The pure rules of the smarter queue: urgent first, commit and branch checks, and folding the same thing said twice.
enum QueueRules {
    /// A repeat only folds into an item recorded at most this long before it.
    static let duplicateWindow: TimeInterval = 30 * 60
    static let duplicateSimilarity = 0.6

    /// True when the said text has "urgent", "asap" or "right now" as whole words ("urgently" does not count).
    static func isUrgent(_ said: String) -> Bool {
        let words = said.lowercased().split { !$0.isLetter }.map(String.init)
        for (index, word) in words.enumerated() {
            if word == "urgent" || word == "asap" { return true }
            if word == "right", index + 1 < words.count, words[index + 1] == "now" { return true }
        }
        return false
    }

    /// Urgent items first; inside each group the order stays as it was (oldest first).
    static func ordered(_ items: [Item]) -> [Item] {
        items.filter { $0.priority == "urgent" } + items.filter { $0.priority != "urgent" }
    }

    /// A commit id: 7 to 40 hex characters.
    static func isValidCommit(_ commit: String) -> Bool {
        (7...40).contains(commit.count) && commit.allSatisfy { $0.isASCII && $0.isHexDigit }
    }

    /// A branch name: not empty, at most 200 characters, no spaces, tabs or new lines.
    static func isValidBranch(_ branch: String) -> Bool {
        !branch.isEmpty && branch.count <= 200 && !branch.contains { $0.isWhitespace || $0.isNewline }
    }

    /// "commit abc1234 on branch fix-it", or nil when the item has neither.
    static func commitLine(_ item: Item) -> String? {
        switch (item.commit, item.branch) {
        case let (commit?, branch?): return "commit \(commit) on branch \(branch)"
        case let (commit?, nil): return "commit \(commit)"
        case let (nil, branch?): return "branch \(branch)"
        default: return nil
        }
    }

    /// Lowercase words of 3 or more letters.
    static func wordSet(_ text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter }.map(String.init).filter { $0.count >= 3 })
    }

    /// Jaccard overlap of the word sets (0 when either has no words).
    static func similarity(_ first: String, _ second: String) -> Double {
        let a = wordSet(first), b = wordSet(second)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return Double(a.intersection(b).count) / Double(a.union(b).count)
    }

    /// Marks an open item as `duplicateOf` an earlier open or in-progress item when all of this holds: the same project (never
    /// across projects), recorded after that one ended and within 30 minutes, the same first pointed element, and the said text
    /// overlaps by 0.6 or more. The original gets the repeat in `alsoSaid`. `canFoldInto` limits which items may be the original
    /// (for example only the ones the caller can see). Items come back in the order they went in.
    static func fold(_ items: [Item], canFoldInto: (Item) -> Bool = { _ in true }) -> [Item] {
        var result = items
        let order = items.indices.sorted { left, right in
            let leftAt = Items.recordedAt(items[left].session) ?? .distantPast
            let rightAt = Items.recordedAt(items[right].session) ?? .distantPast
            return leftAt == rightAt ? items[left].id < items[right].id : leftAt < rightAt
        }
        var originals: [Int] = []
        for index in order {
            let item = items[index]
            if item.status == "open", let found = originals.first(where: { isRepeat(item, of: items[$0]) && canFoldInto(items[$0]) }) {
                result[index].duplicateOf = items[found].id
                result[found].alsoSaid.append("\(item.id): \(item.said)")
                continue
            }
            if item.status == "open" || item.status == "in_progress" { originals.append(index) }
        }
        return result
    }

    static func isRepeat(_ item: Item, of original: Item) -> Bool {
        guard let project = item.project, let originalProject = original.project, samePath(project, originalProject),
              let identity = item.firstElement, identity == original.firstElement,
              let at = Items.recordedAt(item.session), let originalAt = Items.recordedAt(original.session) else { return false }
        let gap = at.timeIntervalSince(originalAt)
        guard gap >= original.duration, gap <= duplicateWindow else { return false }
        return similarity(item.said, original.said) >= duplicateSimilarity
    }

    private static func samePath(_ first: String, _ second: String) -> Bool {
        URL(fileURLWithPath: first).standardized.path == URL(fileURLWithPath: second).standardized.path
    }

    /// The first pointed element as "role|label or title" (lowercased); nil when there is none or it has no name.
    static func elementIdentity(_ points: [PointEvent]) -> String? {
        guard let element = points.sorted(by: { $0.index < $1.index }).compactMap(\.element).first else { return nil }
        let name = [element.label, element.title].compactMap { $0 }.first { !$0.isEmpty }
        guard let role = element.role, let name else { return nil }
        return "\(role)|\(name)".lowercased()
    }
}
