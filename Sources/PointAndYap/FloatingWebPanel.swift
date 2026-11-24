import AppKit
import WebKit

extension Prefs {
    /// The recording pill, the project picker and the done notice are the kit screens (small web panels). Off until the user turns it on.
    static var kitFloating: Bool { UserDefaults.standard.object(forKey: "kitFloating") as? Bool ?? false }
}

/// Whether the floating surfaces are the kit panels or the old SwiftUI ones. One pure decision, used by every surface.
enum FloatingChoice {
    /// The kit panels need the setting on and the built screens (or a dev address) to be there; otherwise keep the SwiftUI ones.
    static func useKit(kitFloating: Bool, uiAvailable: Bool) -> Bool {
        kitFloating && uiAvailable
    }

    /// The decision now, from the saved setting and the app's files. Read each time a surface shows, so the setting works at once.
    @MainActor
    static var useKitNow: Bool {
        useKit(kitFloating: Prefs.kitFloating, uiAvailable: WebHost.uiAvailable)
    }
}

/// The three floating screens. The raw value is the route name the page is told (window.pointrooRoute).
enum FloatingRoute: String {
    case pill
    case picker
    case notice

    /// The size before the page has said how big it is (the page's own margin for the shadow is part of it). The page's size replaces it.
    var defaultSize: NSSize {
        switch self {
        case .pill: return NSSize(width: 392, height: 88)
        case .picker: return NSSize(width: 392, height: 300)
        case .notice: return NSSize(width: 392, height: 240)
        }
    }
}

/// What a floating page posts to the pointrooFloat handler: how big it is, or "open this item in the main window".
enum FloatingPageMessage: Equatable {
    case size(width: Double, height: Double)
    case open(itemId: String)

    static func parse(_ body: [String: Any]) -> FloatingPageMessage? {
        switch body["kind"] as? String {
        case "size":
            guard let width = number(body["width"]), let height = number(body["height"]), width >= 0, height >= 0 else { return nil }
            return .size(width: width, height: height)
        case "open":
            guard let itemId = body["itemId"] as? String, !itemId.isEmpty else { return nil }
            return .open(itemId: itemId)
        default:
            return nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let integer = value as? Int { return Double(integer) }
        return nil
    }
}

/// Where each panel goes on the screen, and how it grows. Pure, so a test can check it.
enum FloatingPlacement {
    /// The pill sits at the top middle, the picker a little lower, the notice at the top right (all inside the visible screen area).
    static func origin(route: FloatingRoute, size: NSSize, visible: NSRect) -> NSPoint {
        switch route {
        case .pill: return NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height)
        case .picker: return NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 44)
        case .notice: return NSPoint(x: visible.maxX - size.width, y: visible.maxY - size.height)
        }
    }

    /// The frame with a new size and the same top-left corner (the top edge stays where it is when the page grows or shrinks).
    static func resized(frame: NSRect, to size: NSSize) -> NSRect {
        NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
    }
}

/// A borderless panel that never takes the app to the front. Only the picker may become the key window (it needs the number keys);
/// its keys go to `onKey` first, so they work even when the page has no focus.
final class FloatingNSPanel: NSPanel {
    var allowsKey = false
    var onKey: (@MainActor (NSEvent) -> Bool)?

    override var canBecomeKey: Bool { allowsKey }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let handler = onKey, handler(event) { return }
        super.sendEvent(event)
    }
}

/// One floating kit screen: a borderless non-activating panel that holds a web view of the same built screens, opened on one route.
/// The page uses the same bridge as the main window. It tells the panel how big it is; a page with nothing to show (0 by 0) hides it.
@MainActor
final class FloatingWebPanel {
    /// How long a shown panel waits for its page to say it has something to show before it hides again.
    static let waitForContentSeconds: UInt64 = 3

    let route: FloatingRoute
    private let panel: FloatingNSPanel
    private let host: WebHost
    private let state: AppState
    private let openItem: (String) -> Void
    private(set) var isShown = false
    private var placed = false
    private var hasContent = false

    var frame: NSRect { panel.frame }

    init(route: FloatingRoute, bridge: WebBridge, state: AppState, openItem: @escaping (String) -> Void) {
        self.route = route
        self.state = state
        self.openItem = openItem
        host = WebHost(bridge: bridge, route: route.rawValue)
        panel = FloatingNSPanel(contentRect: NSRect(origin: .zero, size: route.defaultSize), styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hasShadow = false                    // the page draws its own shadow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.sharingType = .none                  // never in a screenshot
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = host.webView
        if route == .pill { panel.isMovableByWindowBackground = true }
        if route == .picker {
            panel.allowsKey = true
            panel.onKey = { event in ProjectPicker.answerKey(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers) }
        }
        host.onFloatMessage = { [weak self] body in self?.receive(body) }
        host.load()
    }

    /// Puts the panel on screen at its default size and starts telling the page about changes. The page then sets the real size.
    func show() {
        isShown = true
        placed = false
        hasContent = false
        panel.setFrame(NSRect(origin: place(size: route.defaultSize), size: route.defaultSize), display: false)
        host.startEvents(state: state)
        if panel.allowsKey { panel.makeKeyAndOrderFront(nil) } else { panel.orderFrontRegardless() }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.waitForContentSeconds * 1_000_000_000)
            guard let self, self.isShown, !self.hasContent else { return }
            self.hide()
        }
    }

    /// Takes the panel off the screen and stops the events. The page is told its thing is gone, so it is empty when it shows next.
    func hide() {
        guard isShown else { return }
        isShown = false
        panel.orderOut(nil)
        host.stopEvents()
        switch route {
        case .pill: host.emit("recording.changed", ["phase": "idle", "pointCount": 0])
        case .picker: host.emit("picker.changed", ["open": false])
        case .notice: host.emit("notices.changed", ["count": 0])
        }
    }

    private func place(size: NSSize) -> NSPoint {
        let visible = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        return FloatingPlacement.origin(route: route, size: size, visible: visible)
    }

    private func receive(_ body: [String: Any]) {
        switch FloatingPageMessage.parse(body) {
        case .size(let width, let height)?: apply(width: width, height: height)
        case .open(let itemId)?: openItem(itemId)
        case nil: break
        }
    }

    private func apply(width: Double, height: Double) {
        guard isShown else { return }
        if width < 1 || height < 1 {
            // A page that has shown something and now has nothing: hide. An empty page that is still loading is waited for.
            if hasContent { hide() }
            return
        }
        hasContent = true
        let size = NSSize(width: width, height: height)
        if placed {
            panel.setFrame(FloatingPlacement.resized(frame: panel.frame, to: size), display: true)
        } else {
            placed = true
            panel.setFrame(NSRect(origin: place(size: size), size: size), display: true)
        }
    }
}

/// The three floating panels of the app, made when first needed. AppDelegate decides (FloatingChoice) whether to use them.
@MainActor
final class FloatingSurfaces {
    private let state: AppState
    private let makeBridge: () -> WebBridge
    private let openItem: (String) -> Void
    private var panels: [FloatingRoute: FloatingWebPanel] = [:]

    init(state: AppState, makeBridge: @escaping () -> WebBridge, openItem: @escaping (String) -> Void) {
        self.state = state
        self.makeBridge = makeBridge
        self.openItem = openItem
    }

    private func panel(for route: FloatingRoute) -> FloatingWebPanel {
        if let existing = panels[route] { return existing }
        let made = FloatingWebPanel(route: route, bridge: makeBridge(), state: state, openItem: openItem)
        panels[route] = made
        return made
    }

    func showPill() { panel(for: .pill).show() }

    func hidePill() { panels[.pill]?.hide() }

    /// The pill's frame in screen coordinates while it is on screen, else nil.
    var pillFrame: NSRect? {
        guard let pill = panels[.pill], pill.isShown else { return nil }
        return pill.frame
    }

    /// Shows the picker panel for the open picker. The handle hides it again (ProjectPicker calls it when the picker is answered).
    func showPicker() -> PickerHandle {
        let picker = panel(for: .picker)
        picker.show()
        return PickerHandle(close: { [weak picker] in picker?.hide() })
    }

    func showNotice() { panel(for: .notice).show() }

    func hideNotice() { panels[.notice]?.hide() }
}
