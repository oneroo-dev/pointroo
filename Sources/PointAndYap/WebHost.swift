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
