import XCTest
@testable import PointAndYap

/// T1: trashed items are never handed out, and an item whose agent session is gone goes back to open.
final class TrashAndDeadSessionTests: XCTestCase {
    override class func setUp() { _ = PointAndYapTests.root }

    override func tearDown() {
        LiveSessions.unregister()
    }

    private func makeSession(_ id: String, project: String) throws -> URL {
        let directory = try T1Support.makeSession(id, project: project)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func status(of itemId: String) -> String? {
        Items.all().first { $0.id == itemId }?.status
    }

    private func trashedItem(_ session: String, project: String) throws -> String {
        _ = try makeSession(session, project: project)
        let itemId = "\(session)#1"
        XCTAssertEqual(Items.set([itemId], status: "trashed", agent: "user", note: nil).changed, [itemId])
        XCTAssertEqual(status(of: itemId), "trashed")
        return itemId
    }

    func testATrashedItemIsNotHandedOutByOpenItemsEvenWhenTaking() throws {
        let project = "/work/t1-trash-a"
        let itemId = try trashedItem("2031-06-01_100000", project: project)
        XCTAssertFalse(Items.openItems(limit: 20, take: false, agent: "a", project: project).map(\.id).contains(itemId))
        XCTAssertFalse(Items.openItems(limit: 20, take: true, agent: "a", project: project, unrouted: .never).map(\.id).contains(itemId))
        XCTAssertEqual(status(of: itemId), "trashed", "taking left it alone")
        XCTAssertNil(Items.readState(PointAndYapTests.root.appendingPathComponent("2031-06-01_100000"))?.items["1"]?.pid)
    }

    func testGetOpenItemsForAProjectAndForAllNeverMentionsATrashedItem() throws {
        let project = "/work/t1-trash-b"
        let itemId = try trashedItem("2031-06-02_100000", project: project)
        let connection = MCPConnection(cwd: project)
        XCTAssertFalse(T1Support.text(connection.call("get_open_items", ["images": false, "take": false])).contains(itemId))
        XCTAssertFalse(T1Support.text(connection.call("get_open_items", ["images": false, "take": false, "scope": "all"])).contains(itemId))
        XCTAssertFalse(T1Support.text(connection.call("get_open_items", ["images": false, "take": true])).contains(itemId))
        XCTAssertEqual(status(of: itemId), "trashed")
    }

    func testWaitForNextDoesNotTakeATrashedItem() throws {
        let project = "/work/t1-trash-c"
        let itemId = try trashedItem("2031-06-03_100000", project: project)
        let connection = MCPConnection(cwd: project, startedAt: Date().addingTimeInterval(-3600))
        let reply = connection.call("wait_for_next", ["timeout_seconds": 0, "images": false])
        XCTAssertTrue(T1Support.text(reply).hasPrefix("Nothing new yet"), T1Support.text(reply))
        XCTAssertEqual(status(of: itemId), "trashed")
    }

    func testListItemsLeavesATrashedItemOutUnlessTrashedIsAsked() throws {
        let project = "/work/t1-trash-d"
        let itemId = try trashedItem("2031-06-04_100000", project: project)
        let connection = MCPConnection(cwd: project)
        XCTAssertFalse(T1Support.text(connection.call("list_items", [:])).contains(itemId))
        XCTAssertFalse(T1Support.text(connection.call("list_items", ["status": "open"])).contains(itemId))
        XCTAssertFalse(T1Support.text(connection.call("list_items", ["status": "done"])).contains(itemId))
        let trashed = T1Support.text(connection.call("list_items", ["status": "trashed"]))
        XCTAssertTrue(trashed.contains("\(itemId) [trashed"), trashed)
    }

    func testStartItemsRefusesATrashedItemAndSaysItIsInTheTrash() throws {
        let project = "/work/t1-trash-e"
        let itemId = try trashedItem("2031-06-05_100000", project: project)
        let reply = MCPConnection(cwd: project).call("start_items", ["ids": [itemId]])
        XCTAssertEqual(reply["isError"] as? Bool, true)
        XCTAssertTrue(T1Support.text(reply).contains("in the trash"), T1Support.text(reply))
        XCTAssertEqual(status(of: itemId), "trashed")
        let direct = Items.set([itemId], status: "in_progress", agent: "a", note: nil)
        XCTAssertEqual(direct.changed, [])
        XCTAssertEqual(direct.missing, ["\(itemId) (in the trash)"])
    }

    func testReleaseItemsRefusesATrashedItem() throws {
        let project = "/work/t1-trash-g"
        let itemId = try trashedItem("2031-06-07_100000", project: project)
        let reply = MCPConnection(cwd: project).call("release_items", ["ids": [itemId], "note": "back"])
        XCTAssertEqual(reply["isError"] as? Bool, true)
        XCTAssertTrue(T1Support.text(reply).contains("\(itemId) (in the trash)"), T1Support.text(reply))
        XCTAssertEqual(status(of: itemId), "trashed")
    }

    func testMarkDoneRefusesATrashedItem() throws {
        let project = "/work/t1-trash-h"
        let itemId = try trashedItem("2031-06-08_100000", project: project)
        let reply = MCPConnection(cwd: project).call("mark_done", ["ids": [itemId], "note": "fixed"])
        XCTAssertEqual(reply["isError"] as? Bool, true)
        XCTAssertTrue(T1Support.text(reply).contains("\(itemId) (in the trash)"), T1Support.text(reply))
        XCTAssertEqual(status(of: itemId), "trashed")
    }

    func testAMixedCallChangesTheLiveItemAndRefusesTheTrashedOne() throws {
        let project = "/work/t1-trash-i"
        let trashedId = try trashedItem("2031-06-09_100000", project: project)
        _ = try makeSession("2031-06-09_100100", project: "/work/t1-trash-i2")
        let liveId = "2031-06-09_100100#1"
        let reply = MCPConnection(cwd: project).call("mark_done", ["ids": [trashedId, liveId], "note": "ok"])
        XCTAssertNil(reply["isError"])
        XCTAssertTrue(T1Support.text(reply).contains("Done: \(liveId)"), T1Support.text(reply))
        XCTAssertTrue(T1Support.text(reply).contains("\(trashedId) (in the trash)"), T1Support.text(reply))
        XCTAssertEqual(status(of: trashedId), "trashed")
        XCTAssertEqual(status(of: liveId), "done")
    }

    func testReopeningATrashedItemBringsItBackToTheQueue() throws {
        let project = "/work/t1-trash-f"
        let itemId = try trashedItem("2031-06-06_100000", project: project)
        XCTAssertEqual(WebBridge.changeItemStatus(id: itemId, status: "open", note: nil), .changed)
        XCTAssertEqual(status(of: itemId), "open")
        XCTAssertTrue(Items.openItems(limit: 20, take: false, agent: "a", project: project, unrouted: .never).map(\.id).contains(itemId))
    }

    private func takeByASession(_ session: String, pid: Int32?, secondsAgo: Double) throws -> URL {
        let directory = try makeSession(session, project: "/work/t1-dead-\(session)")
        var state = ItemState(source: "session")
        state.items["1"] = .init(status: "in_progress", by: "a", at: Date().addingTimeInterval(-secondsAgo), note: nil, pid: pid)
        XCTAssertTrue(Items.writeState(state, directory))
        return directory
    }

    func testAnItemOfAGoneSessionIsHandedOutAgainAndTheNewTakerIsRecorded() throws {
        let session = "2031-06-10_100000"
        let project = "/work/t1-dead-\(session)"
        _ = try takeByASession(session, pid: 2_000_000_000, secondsAgo: 300)
        XCTAssertEqual(status(of: "\(session)#1"), "open", "no live file for that pid: the session is gone")
        let handed = Items.openItems(limit: 5, take: true, agent: "b", project: project, unrouted: .never, takerPid: 777)
        XCTAssertEqual(handed.map(\.id), ["\(session)#1"])
        let entry = try XCTUnwrap(Items.readState(PointAndYapTests.root.appendingPathComponent(session))?.items["1"])
        XCTAssertEqual(entry.by, "b")
        XCTAssertEqual(entry.pid, 777)
        XCTAssertEqual(entry.status, "in_progress")
    }

    func testAnItemOfALiveSessionIsNotHandedOutToAnotherAgent() throws {
        let session = "2031-06-11_100000"
        let project = "/work/t1-dead-\(session)"
        LiveSessions.register(cwd: project, agent: "claude", pid: getpid())
        _ = try takeByASession(session, pid: getpid(), secondsAgo: 1800)
        XCTAssertEqual(status(of: "\(session)#1"), "in_progress")
        XCTAssertTrue(Items.openItems(limit: 5, take: true, agent: "b", project: project, unrouted: .never).isEmpty)
        XCTAssertEqual(Items.readState(PointAndYapTests.root.appendingPathComponent(session))?.items["1"]?.by, "a")
    }

    func testTheSessionComesBackToOpenOnceItsLiveFileIsRemoved() throws {
        let session = "2031-06-12_100000"
        LiveSessions.register(cwd: "/work/t1-dead-\(session)", agent: "claude", pid: getpid())
        _ = try takeByASession(session, pid: getpid(), secondsAgo: 600)
        XCTAssertEqual(status(of: "\(session)#1"), "in_progress")
        LiveSessions.unregister(pid: getpid())
        XCTAssertEqual(status(of: "\(session)#1"), "open")
    }

    func testTheClosedSessionGraceIsTwoMinutes() throws {
        XCTAssertEqual(Items.closedSessionGrace, 120)
        let inside = try takeByASession("2031-06-13_100000", pid: 4242, secondsAgo: 100)
        let outside = try takeByASession("2031-06-13_100100", pid: 4242, secondsAgo: 140)
        var asked: [Int32] = []
        func first(_ directory: URL) -> String? {
            Items.items(in: directory, state: Items.readState(directory), isTakerAlive: { asked.append($0); return false }).items.first?.status
        }
        XCTAssertEqual(first(inside), "in_progress", "a slow start never frees the item")
        XCTAssertTrue(asked.isEmpty, "the taker is not even looked up inside the grace time")
        XCTAssertEqual(first(outside), "open")
        XCTAssertEqual(asked, [4242])
    }

    func testAGoneSessionDoesNotFreeAnItemThatIsDoneOrTrashed() throws {
        let done = try takeByASession("2031-06-14_100000", pid: 4242, secondsAgo: 600)
        var state = try XCTUnwrap(Items.readState(done))
        state.items["1"] = .init(status: "done", by: "a", at: Date().addingTimeInterval(-600), note: "ok", pid: 4242)
        Items.writeState(state, done)
        XCTAssertEqual(Items.items(in: done, state: Items.readState(done), isTakerAlive: { _ in false }).items.first?.status, "done")
        let trashed = try takeByASession("2031-06-14_100100", pid: 4242, secondsAgo: 600)
        var other = try XCTUnwrap(Items.readState(trashed))
        other.items["1"] = .init(status: "trashed", by: "user", at: Date().addingTimeInterval(-600), note: nil, pid: 4242)
        Items.writeState(other, trashed)
        XCTAssertEqual(Items.items(in: trashed, state: Items.readState(trashed), isTakerAlive: { _ in false }).items.first?.status, "trashed")
    }

    func testTheOlderTakenNameAlsoGoesBackWhenItsSessionIsGone() throws {
        let directory = try makeSession("2031-06-15_100000", project: "/work/t1-dead-old")
        var state = ItemState(source: "session")
        state.items["1"] = .init(status: "taken", by: "a", at: Date().addingTimeInterval(-600), note: nil, pid: 4242)
        Items.writeState(state, directory)
        XCTAssertEqual(Items.items(in: directory, state: Items.readState(directory), isTakerAlive: { _ in false }).items.first?.status, "open")
        XCTAssertEqual(Items.items(in: directory, state: Items.readState(directory), isTakerAlive: { _ in true }).items.first?.status, "in_progress")
    }
}
