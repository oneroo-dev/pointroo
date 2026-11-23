import Foundation
import CoreGraphics

/// Global screen coordinates use the top-left origin of the primary display (as Accessibility and CGDisplayBounds do).
struct Pt: Codable { var x: Double; var y: Double }

struct Rect: Codable {
    var x: Double; var y: Double; var w: Double; var h: Double
    init(_ r: CGRect) { x = r.origin.x; y = r.origin.y; w = r.width; h = r.height }
    var cg: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

struct Frame: Codable {
    var file: String          // frames/003.jpg
    var t: Double             // seconds since session start
    var display: Rect         // the display's frame in global points
    var scale: Double         // image pixels per point
    var reason: String        // start, point, click, interval
}

struct Element: Codable {
    var role: String?
    var subrole: String?
    var title: String?
    var label: String?        // AXDescription
    var value: String?
    var help: String?
    var identifier: String?   // AXIdentifier: source tags of apps we build land here
    var frame: Rect?
    var path: [String]        // ancestors, outermost first, "AXWindow 'Settings'"
    var domIdentifier: String? = nil   // web pages: the element's id attribute (AXDOMIdentifier)
    var domClasses: [String]? = nil    // web pages: the element's class names (AXDOMClassList)
}

extension Element {
    static let maxClasses = 6
    static let maxClassLength = 40

    /// Turns raw web attributes into what we store: empty id and empty class lists become nil.
    static func cleanWebAttributes(identifier: String?, classes: [String]?) -> (identifier: String?, classes: [String]?) {
        let trimmedIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let keptClasses = (classes ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return ((trimmedIdentifier?.isEmpty ?? true) ? nil : trimmedIdentifier, keptClasses.isEmpty ? nil : keptClasses)
    }

    /// The text added to a point line for a web element, like `, web id "save", classes btn primary`. Empty for native elements.
    static func webText(_ element: Element?) -> String {
        guard let element else { return "" }
        var text = ""
        if let identifier = element.domIdentifier, !identifier.isEmpty { text += ", web id \"\(identifier)\"" }
        if let classes = element.domClasses, !classes.isEmpty {
            let shown = classes.prefix(maxClasses).map { String($0.trimmingCharacters(in: .whitespaces).prefix(maxClassLength)) }
            text += ", classes " + shown.joined(separator: " ")
        }
        return text
    }
}

struct PointEvent: Codable {
    var index: Int
    var t: Double
    var end: Double           // when the cursor moved on
    var at: Pt
    var kind: String          // dwell or click
    var app: String?
    var bundleID: String?
    var window: String?
    var url: String?
    var element: Element?
    var frame: String?        // the frame taken for it
}

struct Sample: Codable { var t: Double; var x: Double; var y: Double; var down: Bool }

struct SessionEvents: Codable {
    var started: Date
    var duration: Double
    var samples: [Sample]
    var points: [PointEvent]
    var frames: [Frame]
}

struct Word: Codable { var text: String; var start: Double; var end: Double }

enum Paths {
    /// ~/Pointroo/sessions; POINTANDYAP_SESSIONS points elsewhere (tests).
    static let root = ProcessInfo.processInfo.environment["POINTANDYAP_SESSIONS"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pointroo/sessions")
    /// POINTANDYAP_SUPPORT points elsewhere (tests).
    static let support = ProcessInfo.processInfo.environment["POINTANDYAP_SUPPORT"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Pointroo")

    static var keyFile: URL { support.appendingPathComponent("anthropic-key") }

    static func newSession() -> URL {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        let dir = root.appendingPathComponent(f.string(from: Date()))
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("frames"), withIntermediateDirectories: true)
        return dir
    }

    static func latest() -> URL? {
        let items = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.hasDirectoryPath }.sorted { $0.lastPathComponent < $1.lastPathComponent }.last
    }
}

extension JSONEncoder {
    static let pretty: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
