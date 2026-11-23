import AppKit
import XCTest
@testable import PointAndYap

final class RedactTests: XCTestCase {
    func ranges(_ line: String) -> [String] { Redact.secretRanges(in: line).map { String(line[$0]) } }

    func testFindsEachKnownSecretShape() {
        let secrets = [
            "sk-abcdefghijklmnop1234", "sk_live_abcdef123456", "pk_live_abcdef123456", "ghp_abcdefghij1234567890",
            "gho_abcdefghij1234567890", "github_pat_11ABCDEFG0abcdefgh", "glpat-abcdefghij1234567890",
            "xoxb-1234567890-abcdefghij", "AKIAABCDEFGHIJKLMNOP", "AIza" + String(repeating: "a1B2", count: 8) + "abc",
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.abc123def",
            String(repeating: "a1b2c3d4", count: 8),
            "Zm9vYmFyYmF6UXVYMTIzNDU2Nzg5MEFCQ0RFRkdISUpLTE1O",
        ]
        for secret in secrets { XCTAssertTrue(Redact.isSecret(secret), secret) }
    }

    func testLeavesPlainWordsAndGitIdsAlone() {
        let plain = [
            "Save", "Settings", "Open Pointroo", "This button should be blue, not gray.", "12345", "https://example.com/docs/page",
            "da39a3ee5e6b4b0d3255bfef95601890afd80709", "sk-learn", "password", "token",
        ]
        for text in plain { XCTAssertFalse(Redact.isSecret(text), text) }
        for text in plain { XCTAssertEqual(ranges(text), [], text) }
    }

    func testLabelWordsAloneAreNotSecrets() {
        for line in ["Reset password", "Password manager", "Enter your API key below", "Show tokens", "Settings > Password", "token: abc"] {
            XCTAssertEqual(ranges(line), [], line)
        }
    }

    func testCoversOnlyTheValueAfterALabel() {
        XCTAssertEqual(ranges("password: Xk29!dfQ77zz"), ["Xk29!dfQ77zz"])
        XCTAssertEqual(ranges("export API_TOKEN=abcd1234efgh"), ["abcd1234efgh"])
        XCTAssertEqual(ranges("commit da39a3ee5e6b4b0d3255bfef95601890afd80709 fixed it"), [])
    }

    func testCoversOnlyTheTokenInALongLine() {
        let line = "curl -H 'Authorization: Bearer' -u user:glpat-abcdefghij1234567890 https://example.com"
        XCTAssertEqual(ranges(line), ["glpat-abcdefghij1234567890"])
    }

    func testCoversAPrivateKeyLine() {
        let line = "-----BEGIN RSA PRIVATE KEY-----"
        XCTAssertEqual(ranges(line), [line])
    }

    func image(_ text: String, width: Int = 1600, height: Int = 160) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (text as NSString).draw(at: CGPoint(x: 20, y: 40), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 64, weight: .regular),
            .foregroundColor: NSColor(calibratedRed: 0, green: 0, blue: 0.5, alpha: 1)])
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }

    /// The share of near-white pixels in a band of the image, from and to as fractions of the width.
    func whiteShare(_ image: CGImage, from: Double, to: Double) -> Double {
        let rep = NSBitmapImageRep(cgImage: image)
        var white = 0, total = 0
        for x in stride(from: Int(Double(image.width) * from), to: Int(Double(image.width) * to), by: 2) {
            for y in stride(from: 40, to: 120, by: 2) {
                total += 1
                if let color = rep.colorAt(x: x, y: y), color.brightnessComponent > 0.9 { white += 1 }
            }
        }
        return Double(white) / Double(max(total, 1))
    }

    func testCoversASecretInARealImage() {
        let result = Redact.blur(image("sk-live_ABCDEF1234567890abcdef"))
        XCTAssertTrue(result.changed)
        XCTAssertLessThan(whiteShare(result.image, from: 0.0, to: 0.5), 0.05)
    }

    func testCoversOnlyTheSecretBoxNotTheOtherWords() {
        let result = Redact.blur(image("Save sk-live_ABCDEF1234567890abcdef"))
        XCTAssertTrue(result.changed)
        XCTAssertGreaterThan(whiteShare(result.image, from: 0.0, to: 0.12), 0.5)
    }

    func testLeavesAnImageWithPlainTextUnchanged() {
        XCTAssertFalse(Redact.blur(image("Open Pointroo and press Save")).changed)
    }

    func testLeavesAnImageWithNoTextUnchanged() {
        XCTAssertFalse(Redact.blur(image("")).changed)
    }

    func temporarySession() -> (dir: URL, events: SessionEvents) {
        _ = PointAndYapTests.root
        let source = Bundle.module.url(forResource: "Fixtures/2026-10-17_120000", withExtension: nil)!
        let dir = PointAndYapTests.root.appendingPathComponent("redact-\(UUID().uuidString)")
        try! FileManager.default.copyItem(at: source, to: dir)
        let events = try! JSONDecoder.iso.decode(SessionEvents.self, from: Data(contentsOf: dir.appendingPathComponent("events.json")))
        return (dir, events)
    }

    func black(_ image: CGImage) -> (image: CGImage, changed: Bool) {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (context.makeImage()!, true)
    }

    func brightness(_ url: URL) -> Double {
        let rep = NSBitmapImageRep(data: try! Data(contentsOf: url))!
        return rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.brightnessComponent ?? 1
    }

    func testRedactsFramesBeforeTheCropsAreCut() async throws {
        let (dir, events) = temporarySession()
        let frame = dir.appendingPathComponent(events.frames[0].file)
        XCTAssertGreaterThan(brightness(frame), 0.1)
        let markdown = await Process.run(dir: dir, log: { _ in }, redactSecrets: true, redactor: { self.black($0) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("redacted").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("session.md").path))
        XCTAssertFalse(markdown.isEmpty)
        for file in events.frames.map(\.file) { XCTAssertLessThan(brightness(dir.appendingPathComponent(file)), 0.05, file) }
        let crops = try FileManager.default.contentsOfDirectory(at: dir.appendingPathComponent("crops"), includingPropertiesForKeys: nil)
        XCTAssertFalse(crops.isEmpty)
        for crop in crops { XCTAssertLessThan(brightness(crop), 0.05, crop.lastPathComponent) }
    }

    func testMarkerExistsAndSessionMdIsNotThereWhileRedacting() async throws {
        let (dir, _) = temporarySession()
        let sessionFile = dir.appendingPathComponent("session.md")
        try? FileManager.default.removeItem(at: sessionFile)
        var sessionSeenDuringRedaction = false
        _ = await Process.run(dir: dir, log: { _ in }, redactSecrets: true, redactor: {
            if FileManager.default.fileExists(atPath: sessionFile.path) { sessionSeenDuringRedaction = true }
            return ($0, false)
        })
        XCTAssertFalse(sessionSeenDuringRedaction)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("redacted").path))
    }

    func testDoesNotTouchFramesWhenTheToggleIsOff() async throws {
        let (dir, events) = temporarySession()
        let frame = dir.appendingPathComponent(events.frames[0].file)
        let before = try Data(contentsOf: frame)
        var called = false
        _ = await Process.run(dir: dir, log: { _ in }, redactSecrets: false, redactor: { called = true; return self.black($0) })
        XCTAssertFalse(called)
        XCTAssertEqual(try Data(contentsOf: frame), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("redacted").path))
    }

    func testDoesNotRewriteAFrameWhenNothingChanged() async throws {
        let (dir, events) = temporarySession()
        let frame = dir.appendingPathComponent(events.frames[0].file)
        let before = try Data(contentsOf: frame)
        _ = await Process.run(dir: dir, log: { _ in }, redactSecrets: true, redactor: { ($0, false) })
        XCTAssertEqual(try Data(contentsOf: frame), before)
    }

    func testSkipsFramesThatAreAlreadyRedacted() async throws {
        let (dir, events) = temporarySession()
        try Data().write(to: dir.appendingPathComponent("redacted"))
        var called = false
        let changed = await Redact.redactFrames(dir: dir, files: events.frames.map(\.file), redactor: { called = true; return ($0, false) })
        XCTAssertEqual(changed, 0)
        XCTAssertFalse(called)
    }
}
