import XCTest
@testable import PointAndYap

final class WebImagesTests: XCTestCase {
    override class func setUp() { _ = PointAndYapTests.root }

    private let sessionId = "web-images-session"
    private var root: URL { PointAndYapTests.root }
    private var sessionFolder: URL { root.appendingPathComponent(sessionId) }
    private var outsideFolder: URL { root.deletingLastPathComponent().appendingPathComponent("web-images-outside") }

    override func setUpWithError() throws {
        let manager = FileManager.default
        try? manager.removeItem(at: sessionFolder)
        try? manager.removeItem(at: outsideFolder)
        for folder in ["crops", "frames", "after"] {
            try manager.createDirectory(at: sessionFolder.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try manager.createDirectory(at: outsideFolder, withIntermediateDirectories: true)
        try Data("jpg".utf8).write(to: sessionFolder.appendingPathComponent("crops/01.jpg"))
        try Data("png".utf8).write(to: sessionFolder.appendingPathComponent("frames/f1.PNG"))
        try Data("jpg".utf8).write(to: sessionFolder.appendingPathComponent("after/01.jpg"))
        try Data("caf".utf8).write(to: sessionFolder.appendingPathComponent("audio.caf"))
        try Data("{}".utf8).write(to: sessionFolder.appendingPathComponent("state.json"))
        try Data("secret".utf8).write(to: sessionFolder.appendingPathComponent("crops/notes.txt"))
        try Data("secret".utf8).write(to: outsideFolder.appendingPathComponent("secret.jpg"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: sessionFolder)
        try? FileManager.default.removeItem(at: outsideFolder)
    }

    private func served(_ text: String) -> URL? {
        guard let url = URL(string: text) else { return nil }
        return WebImages.file(for: url, root: root)
    }

    func testCropIsServed() throws {
        let file = try XCTUnwrap(served(WebImages.url(session: sessionId, relative: "crops/01.jpg")))
        XCTAssertEqual(file.lastPathComponent, "01.jpg")
        XCTAssertEqual(WebImages.mimeType(of: file), "image/jpeg")
    }

    func testAfterShotIsServed() {
        XCTAssertNotNil(served(WebImages.url(session: sessionId, relative: "after/01.jpg")))
    }

    func testFramePngWithCapitalExtensionIsServed() throws {
        let file = try XCTUnwrap(served(WebImages.url(session: sessionId, relative: "frames/f1.PNG")))
        XCTAssertEqual(WebImages.mimeType(of: file), "image/png")
    }

    func testDotDotInPathIsRefused() {
        XCTAssertNil(served("pointroo-image://session/\(sessionId)/crops/../audio.caf"))
        XCTAssertNil(served("pointroo-image://session/\(sessionId)/crops/../../web-images-outside/secret.jpg"))
        XCTAssertNil(served("pointroo-image://session/../\(sessionId)/crops/01.jpg"))
    }

    func testEncodedDotDotIsRefused() {
        XCTAssertNil(served("pointroo-image://session/\(sessionId)/crops/%2e%2e/audio.caf"))
        XCTAssertNil(served("pointroo-image://session/\(sessionId)/crops/%2E%2E/%2e%2e/web-images-outside/secret.jpg"))
        XCTAssertNil(served("pointroo-image://session/%2e%2e/\(sessionId)/crops/01.jpg"))
    }

    func testEncodedSlashIsRefused() {
        XCTAssertNil(served("pointroo-image://session/\(sessionId)/crops%2F01.jpg"))
        XCTAssertNil(served("pointroo-image://session/\(sessionId)%2Fcrops/01.jpg"))
    }

    func testAbsolutePathIsRefused() {
        XCTAssertNil(served("pointroo-image://session/\(sessionId)//etc/passwd.jpg"))
        XCTAssertNil(served("pointroo-image://session//\(sessionFolder.path)/crops/01.jpg"))
        XCTAssertNil(served("pointroo-image://session/\(sessionId)/%2Fetc/x.jpg"))
    }

    func testSymlinkOutOfTheSessionIsRefused() throws {
        try FileManager.default.createSymbolicLink(at: sessionFolder.appendingPathComponent("crops/link.jpg"),
                                                   withDestinationURL: outsideFolder.appendingPathComponent("secret.jpg"))
        XCTAssertNil(served(WebImages.url(session: sessionId, relative: "crops/link.jpg")))
        try FileManager.default.createSymbolicLink(at: sessionFolder.appendingPathComponent("frames/linkdir"),
                                                   withDestinationURL: outsideFolder)
        XCTAssertNil(served(WebImages.url(session: sessionId, relative: "frames/linkdir/secret.jpg")))
    }

    func testSymlinkInsideTheSessionIsAllowed() throws {
        try FileManager.default.createSymbolicLink(at: sessionFolder.appendingPathComponent("crops/same.jpg"),
                                                   withDestinationURL: sessionFolder.appendingPathComponent("after/01.jpg"))
        XCTAssertNotNil(served(WebImages.url(session: sessionId, relative: "crops/same.jpg")))
    }

    func testSymlinkToANonImageInsideTheSessionIsRefused() throws {
        let target = sessionFolder.appendingPathComponent("state.json")
        if !FileManager.default.fileExists(atPath: target.path) { try Data("{}".utf8).write(to: target) }
        try FileManager.default.createSymbolicLink(at: sessionFolder.appendingPathComponent("crops/sneak.jpg"), withDestinationURL: target)
        XCTAssertNil(served(WebImages.url(session: sessionId, relative: "crops/sneak.jpg")))
    }

    func testSessionFolderThatIsASymlinkOutIsRefused() throws {
        let linked = root.appendingPathComponent("web-images-linked")
        try? FileManager.default.removeItem(at: linked)
        defer { try? FileManager.default.removeItem(at: linked) }
        try FileManager.default.createDirectory(at: outsideFolder.appendingPathComponent("crops"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: outsideFolder.appendingPathComponent("crops/01.jpg"))
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outsideFolder)
        XCTAssertNil(served(WebImages.url(session: "web-images-linked", relative: "crops/01.jpg")))
    }

    func testOtherFilesAreRefused() {
        XCTAssertNil(served("pointroo-image://session/\(sessionId)/audio.caf"))
        XCTAssertNil(served("pointroo-image://session/\(sessionId)/state.json"))
        XCTAssertNil(served("pointroo-image://session/\(sessionId)/crops/audio.caf"))
    }

    func testWrongExtensionIsRefused() {
        XCTAssertNil(served("pointroo-image://session/\(sessionId)/crops/notes.txt"))
        XCTAssertNil(served("pointroo-image://session/\(sessionId)/crops/01"))
    }

    func testMissingFileIsRefused() {
        XCTAssertNil(served("pointroo-image://session/\(sessionId)/crops/99.jpg"))
    }

    func testDirectoryIsRefused() throws {
        try FileManager.default.createDirectory(at: sessionFolder.appendingPathComponent("crops/folder.jpg"), withIntermediateDirectories: true)
        XCTAssertNil(served("pointroo-image://session/\(sessionId)/crops/folder.jpg"))
    }

    func testFileOverTwentyMegabytesIsRefused() throws {
        let big = sessionFolder.appendingPathComponent("crops/big.jpg")
        XCTAssertTrue(FileManager.default.createFile(atPath: big.path, contents: nil))
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(WebImages.maxBytes + 1))
        try handle.close()
        XCTAssertNil(served("pointroo-image://session/\(sessionId)/crops/big.jpg"))
    }

    func testUnknownSessionIsRefused() {
        XCTAssertNil(served("pointroo-image://session/no-such-session/crops/01.jpg"))
    }

    func testSessionIdWithSlashOrDotIsRefused() {
        XCTAssertNil(served("pointroo-image://session/a%2Fb/crops/01.jpg"))
        XCTAssertNil(served("pointroo-image://session/.hidden/crops/01.jpg"))
        XCTAssertNil(served("pointroo-image://session//crops/01.jpg"))
    }

    func testFolderOutsideTheAllowedThreeIsRefused() {
        XCTAssertNil(served("pointroo-image://session/\(sessionId)/web-images-outside/secret.jpg"))
    }

    func testWrongSchemeOrHostIsRefused() {
        XCTAssertNil(served("https://session/\(sessionId)/crops/01.jpg"))
        XCTAssertNil(served("pointroo-image://other/\(sessionId)/crops/01.jpg"))
        XCTAssertNil(served("pointroo-image://session/\(sessionId)/crops/01.jpg?x=1"))
    }

    func testUrlBuildingEncodesEachPart() {
        XCTAssertEqual(WebImages.url(session: "a b", relative: "crops/01.jpg"), "pointroo-image://session/a%20b/crops/01.jpg")
    }

    private func crop(_ name: String) -> URL { sessionFolder.appendingPathComponent("crops/\(name)") }

    private func item(crops: [URL]) -> Item {
        Item(id: "\(sessionId)#1", session: sessionId, n: 1, title: "t", body: "b", crops: crops, status: "open", at: nil)
    }

    func testItemDictionaryHasCropURLsInOrder() throws {
        try Data("jpg".utf8).write(to: crop("02.jpg"))
        let dictionary = WebBridge.dictionary(item(crops: [crop("01.jpg"), crop("02.jpg")]))
        XCTAssertEqual(dictionary["cropURLs"] as? [String], [
            "pointroo-image://session/\(sessionId)/crops/01.jpg",
            "pointroo-image://session/\(sessionId)/crops/02.jpg",
        ])
        XCTAssertEqual((dictionary["crops"] as? [String])?.count, 2)
    }

    func testItemDictionaryHasAfterURLOnlyWhenTheFileExists() throws {
        XCTAssertEqual(WebBridge.dictionary(item(crops: []))["afterURL"] as? String,
                       "pointroo-image://session/\(sessionId)/after/01.jpg")
        try FileManager.default.removeItem(at: sessionFolder.appendingPathComponent("after/01.jpg"))
        XCTAssertNil(WebBridge.dictionary(item(crops: []))["afterURL"])
    }
}
