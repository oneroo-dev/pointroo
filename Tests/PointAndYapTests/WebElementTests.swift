import XCTest
@testable import PointAndYap

/// R9: web element id and classes on a recorded point.
final class WebElementTests: XCTestCase {
    private func makePoint(_ element: Element) -> PointEvent {
        PointEvent(index: 0, t: 1, end: 2, at: Pt(x: 1, y: 1), kind: "dwell", app: "Chrome", bundleID: nil,
                   window: nil, url: nil, element: element, frame: nil)
    }

    private func line(_ element: Element) -> String {
        var crops: [URL] = []
        return Items.pointLine(makePoint(element), URL(fileURLWithPath: "/nonexistent-pointroo-test"), &crops)
    }

    func testOldElementJSONDecodes() throws {
        let json = #"{"role":"AXButton","path":["AXWindow 'A'"]}"#
        let element = try JSONDecoder.iso.decode(Element.self, from: Data(json.utf8))
        XCTAssertNil(element.domIdentifier)
        XCTAssertNil(element.domClasses)
        XCTAssertEqual(element.role, "AXButton")
    }

    func testNewFieldsRoundTrip() throws {
        let element = Element(role: "AXGroup", path: [], domIdentifier: "save", domClasses: ["btn", "primary"])
        let data = try JSONEncoder.pretty.encode(element)
        let back = try JSONDecoder.iso.decode(Element.self, from: data)
        XCTAssertEqual(back.domIdentifier, "save")
        XCTAssertEqual(back.domClasses, ["btn", "primary"])
    }

    func testCleanupTurnsEmptyIntoNil() {
        let empty = Element.cleanWebAttributes(identifier: "", classes: [])
        XCTAssertNil(empty.identifier)
        XCTAssertNil(empty.classes)
        let blanks = Element.cleanWebAttributes(identifier: "  ", classes: ["", " "])
        XCTAssertNil(blanks.identifier)
        XCTAssertNil(blanks.classes)
        let kept = Element.cleanWebAttributes(identifier: "x", classes: [" a ", "", "b"])
        XCTAssertEqual(kept.identifier, "x")
        XCTAssertEqual(kept.classes, ["a", "b"])
        let none = Element.cleanWebAttributes(identifier: nil, classes: nil)
        XCTAssertNil(none.identifier)
        XCTAssertNil(none.classes)
    }

    func testPointLineShowsWebIdAndClasses() {
        let text = line(Element(role: "AXGroup", path: [], domIdentifier: "save", domClasses: ["btn", "primary"]))
        XCTAssertTrue(text.contains("web id \"save\""), text)
        XCTAssertTrue(text.contains("classes btn primary"), text)
    }

    func testPointLineShowsOnlyClassesWhenNoId() {
        let text = line(Element(role: "AXGroup", path: [], domClasses: ["card"]))
        XCTAssertFalse(text.contains("web id"), text)
        XCTAssertTrue(text.contains("classes card"), text)
    }

    func testPointLineLimitsClasses() {
        let many = (1...9).map { "c\($0)" }
        let text = line(Element(role: "AXGroup", path: [], domClasses: many))
        XCTAssertTrue(text.contains("classes c1 c2 c3 c4 c5 c6"), text)
        XCTAssertFalse(text.contains("c7"), text)
        let longText = line(Element(role: "AXGroup", path: [], domClasses: [String(repeating: "x", count: 80)]))
        XCTAssertTrue(longText.contains("classes " + String(repeating: "x", count: 40)), longText)
        XCTAssertFalse(longText.contains(String(repeating: "x", count: 41)), longText)
    }

    func testPointLineUnchangedForNativeElement() {
        let element = Element(role: "AXButton", path: [])
        XCTAssertEqual(Element.webText(element), "")
        let text = line(element)
        XCTAssertFalse(text.contains("web id"), text)
        XCTAssertFalse(text.contains("classes"), text)
    }
}
