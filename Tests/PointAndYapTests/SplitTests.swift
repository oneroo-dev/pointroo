import XCTest
@testable import PointAndYap

final class SplitTests: XCTestCase {
    /// Builds words from "text:start" pairs; each word lasts 0.3 s.
    func makeWords(_ spec: [(String, Double)]) -> [Word] {
        spec.map { Word(text: $0.0, start: $0.1, end: $0.1 + 0.3) }
    }

    func makePoint(_ index: Int, at time: Double) -> PointEvent {
        PointEvent(index: index, t: time, end: time + 0.6, at: Pt(x: 10, y: 10), kind: "dwell",
                   app: nil, bundleID: nil, window: nil, url: nil, element: nil, frame: nil)
    }

    func texts(_ part: Split.Part) -> String { part.words.map(\.text).joined(separator: " ") }

    func testNoNextGivesOnePartWithEverything() {
        let words = makeWords([("make", 0), ("this", 0.4), ("red", 0.8)])
        let points = [makePoint(0, at: 0.5)]
        let parts = Split.parts(words: words, points: points)
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(texts(parts[0]), "make this red")
        XCTAssertEqual(parts[0].points.map(\.index), [0])
    }

    func testNextWithAPauseSplitsWordsAndPoints() {
        let words = makeWords([("make", 0), ("this", 0.4), ("red,", 0.8), ("next,", 1.2),
                               ("make", 2.5), ("this", 2.9), ("bigger", 3.3)])
        let points = [makePoint(0, at: 0.5), makePoint(1, at: 3.0)]
        let parts = Split.parts(words: words, points: points)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(texts(parts[0]), "make this red,")
        XCTAssertEqual(texts(parts[1]), "make this bigger")
        XCTAssertEqual(parts[0].points.map(\.index), [0])
        XCTAssertEqual(parts[1].points.map(\.index), [1])
    }

    func testPointDuringThePauseAfterNextJoinsTheNextPart() {
        let words = makeWords([("fix", 0), ("this", 0.4), ("next", 0.8), ("and", 2.0), ("that", 2.4)])
        let points = [makePoint(0, at: 0.2), makePoint(1, at: 1.6)]
        let parts = Split.parts(words: words, points: points)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0].points.map(\.index), [0])
        XCTAssertEqual(parts[1].points.map(\.index), [1])
    }

    func testNextOneAndAndNextAreBreakWordsToo() {
        let words = makeWords([("fix", 0), ("this", 0.4), ("next", 0.8), ("one", 1.2),
                               ("fix", 2.4), ("that", 2.8), ("and", 3.2), ("next", 3.6), ("rename", 4.8), ("it", 5.2)])
        let parts = Split.parts(words: words, points: [])
        XCTAssertEqual(parts.map(texts), ["fix this", "fix that", "rename it"])
    }

    func testNextInsideAPhraseNeverSplits() {
        let phrases: [[(String, Double)]] = [
            [("put", 0), ("it", 0.4), ("next", 0.8), ("to", 1.2), ("the", 1.6), ("logo", 2.0)],
            [("do", 0), ("it", 0.4), ("next", 0.8), ("week", 1.2)],
            [("click", 0), ("the", 0.4), ("next", 0.8), ("button", 1.2)],
            [("the", 0), ("next", 0.4), ("one", 0.8), ("is", 1.2), ("wrong", 1.6)],
        ]
        for phrase in phrases {
            let parts = Split.parts(words: makeWords(phrase), points: [makePoint(0, at: 0.5)])
            XCTAssertEqual(parts.count, 1, phrase.map(\.0).joined(separator: " "))
        }
    }

    func testNextAtTheEndIsDroppedWithoutAnEmptyPart() {
        let words = makeWords([("make", 0), ("this", 0.4), ("red", 0.8), ("next", 1.2)])
        let parts = Split.parts(words: words, points: [makePoint(0, at: 0.5)])
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(texts(parts[0]), "make this red")
    }

    func testAPartWithNoWordsAndNoPointsIsDropped() {
        let words = makeWords([("next", 0), ("fix", 1.5), ("this", 1.9), ("next", 2.3), ("next", 3.5), ("and", 4.7), ("that", 5.1)])
        let parts = Split.parts(words: words, points: [])
        XCTAssertEqual(parts.map(texts), ["fix this", "and that"])
    }

    func testAPartWithOnlyAPointIsKept() {
        let words = makeWords([("fix", 0), ("this", 0.4), ("next", 0.8)])
        let parts = Split.parts(words: words, points: [makePoint(0, at: 0.2), makePoint(1, at: 3.0)])
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts[1].words.isEmpty)
        XCTAssertEqual(parts[1].points.map(\.index), [1])
    }
}
