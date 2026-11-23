import Foundation

/// Splits one recording into several parts when the user says "next" as a spoken break.
/// "next" only counts as a break when it is followed by a pause of 0.6 s or more, or it is the last word.
/// So "next to the logo", "next week" and "the next button" never split.
enum Split {
    static let pause: Double = 0.6

    struct Part {
        var words: [Word]
        var points: [PointEvent]
    }

    /// No break word gives one part with everything, exactly like a recording that was never split.
    /// A part with no words and no points is dropped.
    static func parts(words: [Word], points: [PointEvent]) -> [Part] {
        var cuts: [(first: Int, last: Int)] = []
        var index = 0
        while index < words.count {
            if let last = markerEnd(words, from: index) {
                var first = index
                if first > 0, clean(words[first - 1].text) == "and", words[index].start - words[first - 1].end < pause { first -= 1 }
                cuts.append((first, last))
                index = last + 1
            } else {
                index += 1
            }
        }
        guard !cuts.isEmpty else { return [Part(words: words, points: points)] }

        var out: [Part] = []
        var wordStart = 0
        var timeStart = -Double.infinity
        for cut in cuts {
            let boundary = words[cut.last].end
            out.append(part(words: Array(words[wordStart..<cut.first]), points: points, from: timeStart, to: boundary))
            wordStart = cut.last + 1
            timeStart = boundary
        }
        out.append(part(words: Array(words[wordStart...]), points: points, from: timeStart, to: .infinity))
        return out.filter { !$0.words.isEmpty || !$0.points.isEmpty }
    }

    private static func part(words: [Word], points: [PointEvent], from: Double, to: Double) -> Part {
        Part(words: words, points: points.filter { $0.t >= from && $0.t < to })
    }

    /// If a break word starts at `index`, the index of its last word ("next" or "next one"), else nil.
    private static func markerEnd(_ words: [Word], from index: Int) -> Int? {
        guard clean(words[index].text) == "next" else { return nil }
        var last = index
        if index + 1 < words.count, clean(words[index + 1].text) == "one", words[index + 1].start - words[index].end < pause {
            last = index + 1
        }
        if last == words.count - 1 { return last }
        return words[last + 1].start - words[last].end >= pause ? last : nil
    }

    private static func clean(_ text: String) -> String {
        text.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }
}
