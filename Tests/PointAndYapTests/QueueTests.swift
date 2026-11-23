import XCTest
import AppKit
@testable import PointAndYap

/// R4, the smarter queue: urgent first, commit and branch on done, folding repeats, the "you" rule and the blurred after-shot.
final class QueueTests: XCTestCase {
    override class func setUp() { _ = PointAndYapTests.root }

    private func item(_ id: String, said: String, project: String? = "/work/a", status: String = "open",
                      element: String? = "AXButton|save", duration: Double = 5, priority: String? = nil) -> Item {
        var made = Item(id: id, session: String(id.split(separator: "#")[0]), n: 1, title: said, body: said, crops: [],
                        status: status, at: nil)
        made.said = said
        made.project = project
        made.firstElement = element
        made.duration = duration
        made.priority = priority
        return made
    }

    private func cleanUpLater(_ directories: [URL]) {
        addTeardownBlock { for directory in directories { try? FileManager.default.removeItem(at: directory) } }
    }

    /// A processed copy of the fixture with its own said text and first element name, routed to a project.
    private func makeSession(_ id: String, said: String, title: String = "Save", project: String? = "/work/queue-a") throws -> URL {
        let source = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/2026-10-17_120000", withExtension: nil))
        let target = PointAndYapTests.root.appendingPathComponent(id)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: source, to: target)
        let words = said.split(separator: " ").enumerated().map { Word(text: String($0.element), start: Double($0.offset) * 0.4, end: Double($0.offset) * 0.4 + 0.3) }
        try JSONEncoder().encode(words).write(to: target.appendingPathComponent("transcript.json"))
        let eventsURL = target.appendingPathComponent("events.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: eventsURL)) as? [String: Any])
        var points = try XCTUnwrap(json["points"] as? [[String: Any]])
        var element = try XCTUnwrap(points[0]["element"] as? [String: Any])
        element["title"] = title
        points[0]["element"] = element
        json["points"] = points
        try JSONSerialization.data(withJSONObject: json).write(to: eventsURL)
        let events = try JSONDecoder.iso.decode(SessionEvents.self, from: Data(contentsOf: eventsURL))
        _ = Builder.build(dir: target, events: events, words: words)
        if let project {
            Router.writeRoute(RouteInfo(project: URL(fileURLWithPath: project).lastPathComponent, path: project, how: "said"), to: target)
        }
        cleanUpLater([target])
        return target
    }

    private func text(_ reply: [String: Any]) -> String {
        ((reply["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    func testUrgentWordsMatchWholeWordsOnly() {
        XCTAssertTrue(QueueRules.isUrgent("This is urgent, please fix"))
        XCTAssertTrue(QueueRules.isUrgent("Do it ASAP."))
        XCTAssertTrue(QueueRules.isUrgent("I need this Right Now"))
        XCTAssertFalse(QueueRules.isUrgent("This is urgently needed"))
        XCTAssertFalse(QueueRules.isUrgent("an asaphalt road"))
        XCTAssertFalse(QueueRules.isUrgent("turn right at the corner, now what"))
        XCTAssertFalse(QueueRules.isUrgent("make the button blue"))
    }

    func testUrgentItemsGoFirstAndTheRestKeepTheirOrder() {
        let items = [item("2031-01-01_100000#1", said: "a"), item("2031-01-01_100100#1", said: "b", priority: "urgent"),
                     item("2031-01-01_100200#1", said: "c"), item("2031-01-01_100300#1", said: "d", priority: "urgent")]
        XCTAssertEqual(QueueRules.ordered(items).map(\.said), ["b", "d", "a", "c"])
    }

    func testARecordingWithUrgentGetsPriorityAndIsHandedOutFirst() throws {
        let older = try makeSession("2031-01-02_100000", said: "make the header taller", title: "Header")
        let newer = try makeSession("2031-01-02_100100", said: "this is urgent fix the logo", title: "Logo")
        XCTAssertNil(Items.items(in: older, state: nil).items.first?.priority)
        XCTAssertEqual(Items.items(in: newer, state: nil).items.first?.priority, "urgent")
        let ids = Items.openItems(limit: 5, take: false, agent: "a", project: "/work/queue-a", unrouted: .never).map(\.id)
        XCTAssertEqual(ids, ["2031-01-02_100100#1", "2031-01-02_100000#1"])
        let first = Items.openItems(limit: 1, take: true, agent: "a", project: "/work/queue-a", unrouted: .never)
        XCTAssertEqual(first.map(\.id), ["2031-01-02_100100#1"])
        XCTAssertTrue(text(MCPServer.handOut(first, take: true, images: false)).contains("URGENT"))
    }

    func testOldStateFilesWithoutCommitAndBranchStillDecode() throws {
        let old = Data(#"{"source":"session","items":{"1":{"status":"done","by":"claude","at":"2026-10-17T14:20:00Z","note":"fixed"}}}"#.utf8)
        let state = try JSONDecoder.iso.decode(ItemState.self, from: old)
        XCTAssertEqual(state.items["1"]?.status, "done")
        XCTAssertNil(state.items["1"]?.commit)
        XCTAssertNil(state.items["1"]?.branch)
    }

    func testCommitAndBranchRules() {
        XCTAssertTrue(QueueRules.isValidCommit("abc1234"))
        XCTAssertTrue(QueueRules.isValidCommit(String(repeating: "a", count: 40)))
        XCTAssertFalse(QueueRules.isValidCommit("abc123"), "6 characters")
        XCTAssertFalse(QueueRules.isValidCommit(String(repeating: "a", count: 41)))
        XCTAssertFalse(QueueRules.isValidCommit("abc123g"), "not hex")
        XCTAssertTrue(QueueRules.isValidBranch("fix/the-button"))
        XCTAssertTrue(QueueRules.isValidBranch(String(repeating: "b", count: 200)))
        XCTAssertFalse(QueueRules.isValidBranch(String(repeating: "b", count: 201)))
        XCTAssertFalse(QueueRules.isValidBranch("has space"))
        XCTAssertFalse(QueueRules.isValidBranch("two\nlines"))
        XCTAssertFalse(QueueRules.isValidBranch(""))
    }

    func testMarkDoneStoresCommitAndBranchAndListItemsAndGetSessionShowThem() throws {
        let directory = try makeSession("2031-01-03_100000", said: "make the title bigger", title: "Title", project: "/work/queue-b")
        let connection = MCPConnection(cwd: "/work/queue-b")
        let taken = Items.openItems(limit: 1, take: true, agent: connection.agent, project: "/work/queue-b", unrouted: .never)
        let id = try XCTUnwrap(taken.first?.id)
        let reply = connection.call("mark_done", ["ids": [id], "note": "bigger", "commit": "abc1234def", "branch": "fix/title"])
        XCTAssertNil(reply["isError"], text(reply))
        let stored = Items.items(in: directory, state: Items.readState(directory)).items.first
        XCTAssertEqual(stored?.commit, "abc1234def")
        XCTAssertEqual(stored?.branch, "fix/title")
        XCTAssertTrue(text(MCPServer.listItems("done")).contains("commit abc1234def on branch fix/title"))
        XCTAssertTrue(text(MCPServer.getSession("2031-01-03_100000", images: false)).contains("commit abc1234def on branch fix/title"))
    }

    func testBadCommitOrBranchIsRefusedAndNothingChanges() throws {
        let directory = try makeSession("2031-01-04_100000", said: "make the footer smaller", title: "Footer", project: "/work/queue-c")
        let connection = MCPConnection(cwd: "/work/queue-c")
        let id = try XCTUnwrap(Items.openItems(limit: 1, take: true, agent: connection.agent, project: "/work/queue-c", unrouted: .never).first?.id)
        for arguments in [["commit": "nothex!"], ["commit": "abc12"], ["branch": "has space"], ["branch": "a\nb"]] {
            var all: [String: Any] = ["ids": [id]]
            arguments.forEach { all[$0.key] = $0.value }
            XCTAssertEqual(connection.call("mark_done", all)["isError"] as? Bool, true, "\(arguments)")
        }
        XCTAssertEqual(Items.items(in: directory, state: Items.readState(directory)).items.first?.status, "in_progress")
        XCTAssertNil(connection.call("mark_done", ["ids": [id]])["isError"], "commit and branch stay optional")
    }

    func testMarkDoneToolListsCommitAndBranch() throws {
        let tool = try XCTUnwrap(MCPServer.tools.first { $0["name"] as? String == "mark_done" })
        let schema = try XCTUnwrap(tool["inputSchema"] as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        XCTAssertNotNil(properties["commit"])
        XCTAssertNotNil(properties["branch"])
        XCTAssertTrue(MCPServer.instructions.contains("commit and branch"))
    }

    func testARepeatFoldsIntoTheOpenOriginal() {
        let original = item("2031-02-01_100000#1", said: "make the save button blue")
        let repeated = item("2031-02-01_100200#1", said: "please make the save button blue")
        let folded = QueueRules.fold([original, repeated])
        XCTAssertNil(folded[0].duplicateOf)
        XCTAssertEqual(folded[1].duplicateOf, original.id)
        XCTAssertEqual(folded[0].alsoSaid, ["\(repeated.id): please make the save button blue"])
    }

    func testRepeatsNeverFoldAcrossProjects() {
        let first = item("2031-02-02_100000#1", said: "make the save button blue", project: "/work/a")
        let second = item("2031-02-02_100200#1", said: "make the save button blue", project: "/work/b")
        let unrouted = item("2031-02-02_100300#1", said: "make the save button blue", project: nil)
        XCTAssertNil(QueueRules.fold([first, second, unrouted]).compactMap(\.duplicateOf).first)
        let both = [item("2031-02-02_100400#1", said: "make the save button blue", project: nil),
                    item("2031-02-02_100500#1", said: "make the save button blue", project: nil)]
        XCTAssertTrue(QueueRules.fold(both).allSatisfy { $0.duplicateOf == nil }, "two unrouted items are not known to be the same project")
    }

    func testRepeatNeedsTheSameElementEnoughSharedWordsAndTime() {
        let original = item("2031-02-03_100000#1", said: "make the save button blue")
        func folds(_ other: Item) -> Bool { QueueRules.fold([original, other])[1].duplicateOf != nil }
        XCTAssertTrue(folds(item("2031-02-03_100600#1", said: "make the save button blue")))
        XCTAssertFalse(folds(item("2031-02-03_100600#1", said: "make the save button blue", element: "AXButton|cancel")), "other element")
        XCTAssertFalse(folds(item("2031-02-03_100600#1", said: "make the save button blue", element: nil)), "no element")
        XCTAssertFalse(folds(item("2031-02-03_100600#1", said: "remove the header image")), "different words")
        XCTAssertTrue(folds(item("2031-02-03_103000#1", said: "make the save button blue")), "exactly 30 minutes")
        XCTAssertFalse(folds(item("2031-02-03_103001#1", said: "make the save button blue")), "just over 30 minutes")
        XCTAssertFalse(folds(item("2031-02-03_100003#1", said: "make the save button blue")), "started before the first recording ended")
    }

    func testOnlyOpenOrInProgressItemsTakeRepeats() {
        let done = item("2031-02-04_100000#1", said: "make the save button blue", status: "done")
        let later = item("2031-02-04_100200#1", said: "make the save button blue")
        XCTAssertNil(QueueRules.fold([done, later])[1].duplicateOf)
        let working = item("2031-02-04_100000#1", said: "make the save button blue", status: "in_progress")
        XCTAssertEqual(QueueRules.fold([working, later])[1].duplicateOf, working.id)
        var alreadyDone = later
        alreadyDone.status = "done"
        XCTAssertNil(QueueRules.fold([working, alreadyDone])[1].duplicateOf, "a finished item stays as it is")
    }

    func testTwoRepeatsBothGoToTheOriginal() {
        let original = item("2031-02-05_100000#1", said: "make the save button blue")
        let second = item("2031-02-05_100200#1", said: "make the save button blue")
        let third = item("2031-02-05_100400#1", said: "make the save button blue")
        let folded = QueueRules.fold([original, second, third])
        XCTAssertEqual(folded[1].duplicateOf, original.id)
        XCTAssertEqual(folded[2].duplicateOf, original.id)
        XCTAssertEqual(folded[0].alsoSaid.count, 2)
    }

    func testARepeatIsHiddenFromHandOutButStaysInListItemsAndClosesWithTheOriginal() throws {
        let first = try makeSession("2031-02-06_100000", said: "make the save button blue", project: "/work/queue-d")
        let second = try makeSession("2031-02-06_100200", said: "please make the save button blue", project: "/work/queue-d")
        let connection = MCPConnection(cwd: "/work/queue-d")
        XCTAssertEqual(Items.openItems(limit: 5, take: false, agent: "a", project: "/work/queue-d", unrouted: .never).map(\.id), ["2031-02-06_100000#1"])
        let list = text(MCPServer.listItems(nil))
        XCTAssertTrue(list.contains("2031-02-06_100200#1 [open]"), list)
        XCTAssertTrue(list.contains("duplicate of 2031-02-06_100000#1"), list)
        let taken = Items.openItems(limit: 5, take: true, agent: connection.agent, project: "/work/queue-d", unrouted: .never)
        let shown = text(MCPServer.handOut(taken, take: true, images: false))
        XCTAssertTrue(shown.hasPrefix("1 open item"), shown)
        XCTAssertTrue(shown.contains("Also said"), shown)
        XCTAssertTrue(shown.contains("2031-02-06_100200#1: please make the save button blue"), shown)
        XCTAssertFalse(shown.contains("### Item 2031-02-06_100200#1"), shown)
        let done = text(connection.call("mark_done", ["ids": ["2031-02-06_100000#1"], "note": "blue"]))
        XCTAssertTrue(done.contains("Also closed"), done)
        XCTAssertEqual(Items.items(in: second, state: Items.readState(second)).items.first?.status, "done")
        XCTAssertTrue(Items.items(in: second, state: Items.readState(second)).items.first?.note?.contains("Same as 2031-02-06_100000#1") ?? false)
        XCTAssertEqual(Items.items(in: first, state: Items.readState(first)).items.first?.status, "done")
        XCTAssertTrue(Items.openItems(limit: 5, take: false, agent: "a", project: "/work/queue-d", unrouted: .never).isEmpty, "the repeat does not come back")
    }

    func testRecordingsOfTwoProjectsAreBothHandedOutOnDisk() throws {
        _ = try makeSession("2031-02-07_100000", said: "make the save button blue", project: "/work/queue-e")
        _ = try makeSession("2031-02-07_100200", said: "make the save button blue", project: "/work/queue-f")
        let all = Items.openItems(limit: 5, take: false, agent: "a").filter { $0.session.hasPrefix("2031-02-07") }
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.allSatisfy { $0.duplicateOf == nil })
    }

    func testLastAgentDoneSkipsItemsTheUserMarkedDone() {
        func done(_ id: String, by: String, secondsAgo: Double, project: String) -> Item {
            var made = item(id, said: "x", project: project, status: "done")
            made.by = by
            made.at = Date().addingTimeInterval(-secondsAgo)
            return made
        }
        let agent = done("2031-03-01_100000#1", by: "claude (cms)", secondsAgo: 300, project: "/work/cms")
        let you = done("2031-03-01_100100#1", by: "you", secondsAgo: 10, project: "/work/shop")
        let result = Router.lastAgentDone([agent, you])
        XCTAssertEqual(result?.id, agent.id)
        XCTAssertEqual(result?.path, "/work/cms")
        XCTAssertNil(Router.lastAgentDone([you]))
    }

    private func writeSolidImage(width: Int, height: Int, white: Bool, to url: URL) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: white ? 1 : 0, green: white ? 1 : 0, blue: white ? 1 : 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage())).representation(using: .png, properties: [:]))
        try data.write(to: url)
    }

    private func brightness(of url: URL) throws -> CGFloat {
        let representation = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        let color = try XCTUnwrap(representation.colorAt(x: 5, y: 5)?.usingColorSpace(.sRGB))
        return color.redComponent
    }

    func testAfterShotCropIsRedactedWhenTheSettingIsOn() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("queue-aftershot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("full.png")
        try writeSolidImage(width: 400, height: 300, white: true, to: source)
        let display = CGRect(x: 0, y: 0, width: 400, height: 300)
        var calls = 0
        let blackout: Redact.Redactor = { image in
            calls += 1
            let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return (context.makeImage()!, true)
        }
        let blurred = directory.appendingPathComponent("on/01.jpg")
        XCTAssertTrue(AfterShot.writeCrop(from: source, rect: display, display: display, scale: 1, to: blurred,
                                          redactSecrets: true, redactor: blackout))
        XCTAssertEqual(calls, 1)
        XCTAssertLessThan(try brightness(of: blurred), 0.2)
        let plain = directory.appendingPathComponent("off/01.jpg")
        XCTAssertTrue(AfterShot.writeCrop(from: source, rect: display, display: display, scale: 1, to: plain,
                                          redactSecrets: false, redactor: blackout))
        XCTAssertEqual(calls, 1, "the setting is off: the image is not touched")
        XCTAssertGreaterThan(try brightness(of: plain), 0.8)
    }
}
