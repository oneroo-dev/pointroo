import AppKit
import WebKit

extension Prefs {
    /// A localhost address (for example http://localhost:5173) to load the screens from while building them. Empty or missing = use the app's own files.
    static var webDevURL: String? { UserDefaults.standard.string(forKey: "webDevURL") }
}

/// Makes the web view that shows the kit screens. AppDelegate puts it in the main window when the kitWindow setting is on.
@MainActor
final class WebHost {
    let webView: WKWebView
    let bridge: WebBridge
    private let policy: NavigationPolicy
    private var webEvents = WebEvents()
    private var eventTimer: Timer?
    private var isReadingEvents = false
    /// True once the page has finished loading (its listeners are set up when the page is mounted, before that point).
    private var pageReady = false
    private var pendingFocus = PendingFocus()

    /// The folder inside the app that holds the built screens (Contents/Resources/ui).
    static var bundleFolder: URL? { Bundle.main.resourceURL?.appendingPathComponent("ui", isDirectory: true) }

    /// True when the built screens are in the app (Contents/Resources/ui/index.html), or a dev address is set.
    static var uiAvailable: Bool {
        if devURL(from: Prefs.webDevURL) != nil { return true }
        guard let folder = bundleFolder else { return false }
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.html").path)
    }

    /// What a floating page posts besides bridge calls (its size, "open this item"). Set by the panel that holds this host.
    var onFloatMessage: (([String: Any]) -> Void)?

    /// `route` makes this a floating panel's page: it is "pill", "picker" or "notice", put into window.pointrooRoute before the page
    /// loads (the page then shows that one small screen), and the page may post to the second handler, pointrooFloat. Nil = the main window.
    init(bridge: WebBridge = WebBridge(), route: String? = nil) {
        self.bridge = bridge
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(WebImageHandler(), forURLScheme: WebImages.scheme)   // must come before the web view is made
        let webView = PlainWebView(frame: .zero, configuration: configuration)
        let policy = NavigationPolicy(bundleFolder: Self.bundleFolder, devOrigin: Self.devURL(from: Prefs.webDevURL))
        self.webView = webView
        self.policy = policy
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = policy
        configuration.userContentController.add(WeakScriptHandler(host: self), name: "pointroo")
        if let route {
            // The route names are fixed words (see FloatingRoute), so putting one inside quotes is safe.
            let script = WKUserScript(source: "window.pointrooRoute = \"\(route)\";", injectionTime: .atDocumentStart, forMainFrameOnly: true)
            configuration.userContentController.addUserScript(script)
            configuration.userContentController.add(WeakFloatHandler(host: self), name: "pointrooFloat")
        }
        policy.onFinish = { [weak self] in MainActor.assumeIsolated { self?.pageDidLoad() } }
    }

    private func pageDidLoad() {
        pageReady = true
        if let id = pendingFocus.pageBecameReady() { send(PendingFocus.event(id: id)) }
    }

    private func send(_ event: WebEvents.Event) {
        emit(event.name, event.data)
    }

    /// Asks the page to select an item (event item.focus). If the page has not loaded yet, the id waits and goes out after the load.
    func focusItem(_ id: String) {
        if let now = pendingFocus.request(id, pageReady: pageReady) { send(PendingFocus.event(id: now)) }
    }

    /// Loads the dev address when one is set, else ui/index.html from the app, with read access to that folder only.
    func load() {
        pageReady = false
        if let devURL = Self.devURL(from: Prefs.webDevURL) {
            webView.load(URLRequest(url: devURL))
        } else if let folder = Self.bundleFolder {
            webView.loadFileURL(folder.appendingPathComponent("index.html"), allowingReadAccessTo: folder)
        }
    }

    /// Moves the window with the mouse, like dragging a title bar. Only works right after a left-mouse-down in the web view
    /// (less than about a second old); otherwise it does nothing.
    func performWindowDrag() {
        guard let view = webView as? PlainWebView, let event = view.lastMouseDown,
              event.type == .leftMouseDown, ProcessInfo.processInfo.systemUptime - event.timestamp < 1,
              let window = view.window else { return }
        window.performDrag(with: event)
    }

    /// Tells the page about something (runs window.pointroo.emit).
    func emit(_ name: String, _ data: Any) {
        webView.evaluateJavaScript(WebBridge.emitScript(name: name, data: data), completionHandler: nil)
    }

    /// Starts telling the page about changes, once a second. The disk is read on a background queue; the events go out on the main actor.
    /// AppDelegate calls this when the kit window shows, and stopEvents when it closes or hides.
    func startEvents(state: AppState) {
        stopEvents()
        webEvents = WebEvents()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self, weak state] _ in
            Task { @MainActor [weak self, weak state] in
                guard let self, let state else { return }
                self.tick(state: state)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        eventTimer = timer
        tick(state: state)
    }

    func stopEvents() {
        eventTimer?.invalidate()
        eventTimer = nil
        isReadingEvents = false
    }

    private func tick(state: AppState) {
        let picker = ProjectPicker.snapshot()
        let recording = Self.recordingSnapshot(state: state, pickerOpen: picker != nil)
        for event in webEvents.recording(phase: recording.phase, pointCount: recording.points) + webEvents.picker(picker) {
            emit(event.name, event.data)
        }
        guard !isReadingEvents else { return }
        isReadingEvents = true
        Task.detached(priority: .utility) { [weak self] in
            let items = Items.all()
            let questions = Questions.pending()
            // Read the permissions directly, not through state.refreshAccess(): setting AppState's published values every
            // second would redraw every SwiftUI view that watches it, even when nothing changed.
            let status = AppStatus.readNow()
            let noticeIds = Notices.identifiers(items: items, questions: questions, seen: Set(NoticeStore().seenIds()))
            await self?.finishRead(items: items, questions: questions, status: status, noticeIds: noticeIds)
        }
    }

    private func finishRead(items: [Item], questions: [Question], status: AppStatus, noticeIds: [String]) {
        guard isReadingEvents else { return }   // stopEvents ran while the read was going
        isReadingEvents = false
        guard eventTimer != nil else { return }
        let sent = webEvents.routeSent(items, projectName: { Projects.name(for: $0) })
        for event in webEvents.items(items) + webEvents.questions(questions) + webEvents.notices(noticeIds) + webEvents.status(status) + sent {
            emit(event.name, event.data)
        }
    }

    /// The one recording snapshot: recording.get and recording.changed both use it. "picking" while the project picker is open
    /// (AppState is idle then, but it is waiting for the answer).
    static func recordingSnapshot(state: AppState, pickerOpen: Bool) -> RecordingSnapshot {
        recordingSnapshot(phase: state.phase, pointCount: state.pointCount, pickerOpen: pickerOpen)
    }

    nonisolated static func recordingSnapshot(phase: AppState.Phase, pointCount: Int, pickerOpen: Bool) -> RecordingSnapshot {
        var name = phaseName(phase)
        if pickerOpen, name == "idle" { name = "picking" }
        var startedAt: Date?
        if case .recording(let date) = phase { startedAt = date }
        return RecordingSnapshot(phase: name, startedAt: startedAt, points: pointCount)
    }

    /// recording.changed phase: idle, recording, or processing (every case of AppState.Phase); the snapshot adds picking.
    nonisolated static func phaseName(_ phase: AppState.Phase) -> String {
        switch phase {
        case .idle: return "idle"
        case .recording: return "recording"
        case .processing: return "processing"
        }
    }

    fileprivate func receive(_ body: Any) {
        webView.evaluateJavaScript(bridge.handle(message: body), completionHandler: nil)
    }

    fileprivate func receiveFloat(_ body: Any) {
        guard let message = body as? [String: Any] else { return }
        onFloatMessage?(message)
    }

    /// Only a plain http address on this Mac is allowed as the dev address.
    nonisolated static func devURL(from text: String?) -> URL? {
        guard let text, !text.isEmpty, let url = URL(string: text), url.scheme == "http",
              let host = url.host, ["localhost", "127.0.0.1", "::1"].contains(host), url.port != nil else { return nil }
        return url
    }

    /// The one decision about where the page may go: files inside the bundle folder, and the dev address. Nothing else.
    nonisolated static func allows(_ url: URL, bundleFolder: URL?, devOrigin: URL?) -> Bool {
        if url.isFileURL {
            guard let bundleFolder else { return false }
            let folder = bundleFolder.standardizedFileURL.path
            let path = url.standardizedFileURL.path
            return path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
        }
        guard let devOrigin else { return false }
        return url.scheme == devOrigin.scheme && url.host == devOrigin.host && url.port == devOrigin.port
    }
}

/// A web view with no right-click menu.
private final class PlainWebView: WKWebView {
    /// The last left-mouse-down, kept so the page can ask for a window drag (window.startDrag) right after it.
    var lastMouseDown: NSEvent?

    override func menu(for event: NSEvent) -> NSMenu? { nil }

    override func mouseDown(with event: NSEvent) {
        lastMouseDown = event
        super.mouseDown(with: event)
    }
}

private final class NavigationPolicy: NSObject, WKNavigationDelegate {
    let bundleFolder: URL?
    let devOrigin: URL?
    /// Called on the main thread when a page load has finished.
    var onFinish: (() -> Void)?

    init(bundleFolder: URL?, devOrigin: URL?) {
        self.bundleFolder = bundleFolder
        self.devOrigin = devOrigin
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async { [weak self] in self?.onFinish?() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              WebHost.allows(url, bundleFolder: bundleFolder, devOrigin: devOrigin) else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

/// The same for the second handler, pointrooFloat (a floating page's size and open requests).
private final class WeakFloatHandler: NSObject, WKScriptMessageHandler {
    weak var host: WebHost?

    init(host: WebHost) { self.host = host }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        Task { @MainActor [weak host] in host?.receiveFloat(body) }
    }
}

/// WKUserContentController keeps its handlers alive, so this holds the host weakly to avoid a retain cycle.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var host: WebHost?

    init(host: WebHost) { self.host = host }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        Task { @MainActor [weak host] in host?.receive(body) }
    }
}
