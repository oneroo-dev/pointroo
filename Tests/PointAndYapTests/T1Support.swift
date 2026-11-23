import XCTest
@testable import PointAndYap

/// Shared helpers for the T1 test-gap tests: a processed copy of the fixture recording in the temporary sessions folder.
enum T1Support {
    /// A processed copy of the fixture under its own id (one item, "<id>#1"), with no route and no suggestion, then routed to
    /// `project` as "said" when one is given. The caller removes the folder when the test ends.
    static func makeSession(_ id: String, project: String?) throws -> URL {
        let source = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/2026-10-17_120000", withExtension: nil))
        let target = PointAndYapTests.root.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)
        let events = try JSONDecoder.iso.decode(SessionEvents.self, from: Data(contentsOf: target.appendingPathComponent("events.json")))
        let words = try JSONDecoder().decode([Word].self, from: Data(contentsOf: target.appendingPathComponent("transcript.json")))
        _ = Builder.build(dir: target, events: events, words: words)
        try? FileManager.default.removeItem(at: Router.routeURL(target))
        try? FileManager.default.removeItem(at: Router.suggestURL(target))
        if let project {
            Router.writeRoute(RouteInfo(project: URL(fileURLWithPath: project).lastPathComponent, path: project, how: "said"), to: target)
        }
        return target
    }

    /// The JSON part of `window.pointroo.reply(<id>, <json>)`, read back as an object.
    static func replyObject(_ script: String) throws -> [String: Any] {
        let prefix = "window.pointroo.reply("
        XCTAssertTrue(script.hasPrefix(prefix))
        let inner = String(script.dropFirst(prefix.count).dropLast())
        let split = try XCTUnwrap(inner.range(of: ", {"))
        let json = "{" + inner[split.upperBound...]
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    static func errorCode(_ script: String) throws -> String? {
        ((try replyObject(script))["error"] as? [String: Any])?["code"] as? String
    }

    static func text(_ reply: [String: Any]) -> String {
        ((reply["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
    }
}
