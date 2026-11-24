import Foundation

/// The queue search behind the bridge method items.search. Pure: it gets items and a text, and gives back the matches.
enum ItemSearch {
    struct Match {
        var item: Item
        /// The best field that holds a hit: title, said, body, alsoSaid, note, project or firstElement.
        var field: String
        /// Up to `snippetLength` characters around the first hit, on one line.
        var snippet: String
    }

    static let snippetLength = 80
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// Every item that holds every word of `text` (case and accents ignored) in its title, body, said, alsoSaid, note,
    /// project name or firstElement. Title hits come first, then said/body, then the rest; inside a rank the newest item
    /// comes first (items with no date last, then the order given).
    static func matches(_ items: [Item], text: String, projectName: (String) -> String = Projects.name(for:)) -> [Match] {
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }
        var found: [(match: Match, rank: Int, offset: Int)] = []
        for (offset, item) in items.enumerated() {
            let fields = Self.fields(of: item, projectName: projectName)
            let everyWordFound = words.allSatisfy { word in fields.contains { contains($0.text, word) } }
            guard everyWordFound else { continue }
            guard let best = fields.first(where: { field in words.contains { contains(field.text, $0) } }) else { continue }
            let rank = best.name == "title" ? 0 : (best.name == "said" || best.name == "body" ? 1 : 2)
            found.append((Match(item: item, field: best.name, snippet: snippet(in: best.text, words: words)), rank, offset))
        }
        found.sort { first, second in
            if first.rank != second.rank { return first.rank < second.rank }
            switch (first.match.item.at, second.match.item.at) {
            case let (one?, two?) where one != two: return one > two
            case (_?, nil): return true
            case (nil, _?): return false
            default: return first.offset < second.offset
            }
        }
        return found.map(\.match)
    }

    /// The fields to search, best first, each on one line.
    private static func fields(of item: Item, projectName: (String) -> String) -> [(name: String, text: String)] {
        var all: [(name: String, text: String)] = [
            ("title", item.title), ("said", item.said), ("body", item.body), ("alsoSaid", item.alsoSaid.joined(separator: " ")),
        ]
        if let note = item.note { all.append(("note", note)) }
        if let project = item.project { all.append(("project", projectName(project))) }
        if let firstElement = item.firstElement { all.append(("firstElement", firstElement)) }
        var lines: [(name: String, text: String)] = []
        for field in all {
            let line = oneLine(field.text)
            if !line.isEmpty { lines.append((name: field.name, text: line)) }
        }
        return lines
    }

    private static func oneLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ")
    }

    private static func contains(_ text: String, _ word: String) -> Bool {
        text.range(of: word, options: options) != nil
    }

    /// Up to `snippetLength` characters around the earliest hit of any word.
    private static func snippet(in text: String, words: [String]) -> String {
        let hits = words.compactMap { text.range(of: $0, options: options) }
        guard let first = hits.min(by: { $0.lowerBound < $1.lowerBound }) else { return String(text.prefix(snippetLength)) }
        let characters = Array(text)
        let hitOffset = text.distance(from: text.startIndex, to: first.lowerBound)
        let start = max(0, min(hitOffset - 20, characters.count - snippetLength))
        let end = min(characters.count, start + snippetLength)
        return String(characters[start..<end]).trimmingCharacters(in: .whitespaces)
    }
}
