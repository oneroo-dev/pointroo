import XCTest
import AppKit
@testable import PointAndYap

/// The after-shot logic for the done banner (no screen access needed).
final class CloseLoopTests: XCTestCase {
    override class func setUp() { _ = PointAndYapTests.root }

    private func point(_ x: Double, _ y: Double, index: Int = 0) -> PointEvent {
        PointEvent(index: index, t: 0, end: 1, at: Pt(x: x, y: y), kind: "click", app: nil, bundleID: nil,
                   window: nil, url: nil, element: nil, frame: nil)
    }

    private let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func testCropIsCenteredOnAPointInTheMiddle() {
        let rect = AfterShot.cropRect(for: point(960, 540), display: display)
        XCTAssertEqual(rect, CGRect(x: 510, y: 240, width: 900, height: 600))
    }

    func testCropStaysInsideTheDisplayAtEachEdge() {
        XCTAssertEqual(AfterShot.cropRect(for: point(0, 0), display: display), CGRect(x: 0, y: 0, width: 900, height: 600))
        XCTAssertEqual(AfterShot.cropRect(for: point(1920, 1080), display: display), CGRect(x: 1020, y: 480, width: 900, height: 600))
        XCTAssertEqual(AfterShot.cropRect(for: point(1920, 0), display: display), CGRect(x: 1020, y: 0, width: 900, height: 600))
        XCTAssertEqual(AfterShot.cropRect(for: point(0, 1080), display: display), CGRect(x: 0, y: 480, width: 900, height: 600))
    }

    func testCropOnASecondDisplayWithAnOffsetOrigin() {
        let second = CGRect(x: 1920, y: -200, width: 1440, height: 900)
        let rect = AfterShot.cropRect(for: point(3350, 690), display: second)
        XCTAssertEqual(rect, CGRect(x: 2460, y: 100, width: 900, height: 600))
        XCTAssertTrue(second.contains(rect))
    }

    func testCropOnASmallDisplayIsTheWholeDisplay() {
        let small = CGRect(x: 0, y: 0, width: 800, height: 500)
        XCTAssertEqual(AfterShot.cropRect(for: point(400, 250), display: small), small)
    }

    func testPixelRectUsesTheScale() {
        let pixels = AfterShot.pixelRect(for: CGRect(x: 1020, y: 480, width: 900, height: 600), display: display, scale: 2)
        XCTAssertEqual(pixels, CGRect(x: 2040, y: 960, width: 1800, height: 1200))
    }

    func testBannerNoticeFieldsDefaultToNil() {
        let notice = BannerNotice(project: "p", note: "n")
        XCTAssertNil(notice.before); XCTAssertNil(notice.after); XCTAssertNil(notice.session)
    }

    private func writeSolidJPEG(width: Int, height: Int, to url: URL) {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .jpeg, properties: [:])!
        try! data.write(to: url)
    }

    func testWriteCropMakesAnAfterFileAtMostTwelveHundredWide() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("aftershot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("full.jpg")
        writeSolidJPEG(width: 3840, height: 2160, to: source)
        let target = dir.appendingPathComponent("session/after/01.jpg")
        let rect = AfterShot.cropRect(for: point(960, 540), display: display)
        XCTAssertTrue(AfterShot.writeCrop(from: source, rect: rect, display: display, scale: 2, to: target))
        let image = try XCTUnwrap(NSImage(contentsOf: target)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(image.width, 1200)
        XCTAssertEqual(image.height, 800)
    }

    func testWriteCropFailsQuietlyWhenTheSourceIsMissing() {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("aftershot-none-\(UUID().uuidString)/01.jpg")
        XCTAssertFalse(AfterShot.writeCrop(from: URL(fileURLWithPath: "/nonexistent.jpg"), rect: CGRect(x: 0, y: 0, width: 10, height: 10),
                                           display: display, scale: 2, to: target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    private func sessionWithEvents(_ id: String, points: [PointEvent]) throws -> URL {
        let dir = PointAndYapTests.root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let events = SessionEvents(started: Date(), duration: 5, samples: [], points: points, frames: [])
        try JSONEncoder.pretty.encode(events).write(to: dir.appendingPathComponent("events.json"))
        return dir
    }

    private func item(_ session: String, crops: [URL]) -> Item {
        Item(id: "\(session)#1", session: session, n: 1, title: "title", body: "", crops: crops, status: "done", at: nil, by: "agent", note: "fixed it")
    }

    func testFirstPointComesFromTheCropName() throws {
        let dir = try sessionWithEvents("after-a", points: [point(10, 10, index: 0), point(50, 60, index: 2)])
        let found = AfterShot.firstPoint(of: item("after-a", crops: [dir.appendingPathComponent("crops/03.jpg")]), in: dir)
        XCTAssertEqual(found?.index, 2)
        XCTAssertEqual(found?.at.x, 50)
    }

    func testNoCropsMeansNoPoint() throws {
        let dir = try sessionWithEvents("after-b", points: [point(10, 10)])
        XCTAssertNil(AfterShot.firstPoint(of: item("after-b", crops: []), in: dir))
    }

    func testNoticeWithoutCropsIsPlainAndTakesNoShot() async throws {
        _ = try sessionWithEvents("after-c", points: [point(10, 10)])
        let notice = await AfterShot.notice(item: item("after-c", crops: []), project: "alpha")
        XCTAssertEqual(notice, BannerNotice(project: "alpha", note: "fixed it", itemId: "after-c#1"))
        XCTAssertNil(notice.after)
        XCTAssertFalse(FileManager.default.fileExists(atPath: PointAndYapTests.root.appendingPathComponent("after-c/after").path))
    }

    func testTimeoutGivesNilWhenWorkIsSlowAndCleansUp() async {
        let cleaned = expectation(description: "late work cleaned up")
        let result: Int? = await AfterShot.withTimeout(0.05, cleanup: { cleaned.fulfill() }) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            return 1
        }
        XCTAssertNil(result)
        await fulfillment(of: [cleaned], timeout: 2)
    }

    func testTimeoutGivesTheResultWhenWorkIsFast() async {
        let result: Int? = await AfterShot.withTimeout(2) { 7 }
        XCTAssertEqual(result, 7)
    }
}
