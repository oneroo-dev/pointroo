import AppKit
import WebKit

extension Prefs {
    /// A localhost address (for example http://localhost:5173) to load the screens from while building them. Empty or missing = use the app's own files.
    static var webDevURL: String? { UserDefaults.standard.string(forKey: "webDevURL") }
}

/// Makes the web view that shows the kit screens. It is not wired into any window yet.
@MainActor
final class WebHost {
    let webView: WKWebView
    let bridge: WebBridge
    private let policy: NavigationPolicy
    private var webEvents = WebEvents()
    private var eventTimer: Timer?
    private var isReadingEvents = false

    /// The folder inside the app that holds the built screens (Contents/Resources/ui).
    static var bundleFolder: URL? { Bundle.main.resourceURL?.appendingPathComponent("ui", isDirectory: true) }

    init(bridge: WebBridge = WebBridge()) {
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
    }

    /// Loads the dev address when one is set, else ui/index.html from the app, with read access to that folder only.
    func load() {
        if let devURL = Self.devURL(from: Prefs.webDevURL) {
            webView.load(URLRequest(url: devURL))
        } else if let folder = Self.bundleFolder {
            webView.loadFileURL(folder.appendingPathComponent("index.html"), allowingReadAccessTo: folder)
        }
    }

    /// Tells the page about something (runs window.pointroo.emit).
    func emit(_ name: String, _ data: Any) {
        webView.evaluateJavaScript(WebBridge.emitScript(name: name, data: data), completionHandler: nil)
    }

    /// Starts telling the page about changes, once a second. The disk is read on a background queue; the events go out on the main actor.
    /// Nothing calls this yet: the redesign calls it when it shows the web view.
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
        for event in webEvents.recording(phase: Self.phaseName(state.phase), pointCount: state.pointCount) {
            emit(event.name, event.data)
        }
        guard !isReadingEvents else { return }
        isReadingEvents = true
        Task.detached(priority: .utility) { [weak self] in
            let items = Items.all()
            let questions = Questions.pending()
            await self?.finishRead(items: items, questions: questions)
        }
    }

    private func finishRead(items: [Item], questions: [Question]) {
        guard isReadingEvents else { return }   // stopEvents ran while the read was going
        isReadingEvents = false
        guard eventTimer != nil else { return }
        for event in webEvents.items(items) + webEvents.questions(questions) {
            emit(event.name, event.data)
        }
    }

    /// recording.changed phase: idle, recording, or processing (every case of AppState.Phase).
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
    override func menu(for event: NSEvent) -> NSMenu? { nil }
}

private final class NavigationPolicy: NSObject, WKNavigationDelegate {
    let bundleFolder: URL?
    let devOrigin: URL?

    init(bundleFolder: URL?, devOrigin: URL?) {
        self.bundleFolder = bundleFolder
        self.devOrigin = devOrigin
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

/// WKUserContentController keeps its handlers alive, so this holds the host weakly to avoid a retain cycle.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var host: WebHost?

    init(host: WebHost) { self.host = host }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        Task { @MainActor [weak host] in host?.receive(body) }
    }
}
