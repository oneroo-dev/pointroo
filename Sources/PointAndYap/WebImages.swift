import Foundation
import WebKit

/// Lets a kit page show an item's pictures without giving it file access.
///
/// A page uses `pointroo-image://session/<session id>/<relative path>`, for example
/// `pointroo-image://session/2026-11-23_101500/crops/01.jpg`. The relative path must start with crops, frames or after
/// and end in .jpg, .jpeg or .png. Nothing else is ever served.
enum WebImages {
    static let scheme = "pointroo-image"
    static let host = "session"
    static let allowedFolders: Set<String> = ["crops", "frames", "after"]
    static let allowedExtensions: Set<String> = ["jpg", "jpeg", "png"]
    static let maxBytes = 20 * 1024 * 1024

    /// The address a page can use for one file of a session. `relative` is like "crops/01.jpg".
    static func url(session: String, relative: String) -> String {
        let parts = [session] + relative.split(separator: "/").map(String.init)
        let encoded = parts.map { $0.addingPercentEncoding(withAllowedCharacters: componentCharacters) ?? "" }
        return "\(scheme)://\(host)/" + encoded.joined(separator: "/")
    }

    private static let componentCharacters: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }()

    /// The relative path ("crops/01.jpg") of a crop file that sits in a session folder, or nil when it is not a plain
    /// file of a session under `root`.
    static func relativePath(of file: URL, session: String, root: URL) -> String? {
        let folder = root.appendingPathComponent(session, isDirectory: true).standardizedFileURL.pathComponents
        let parts = file.standardizedFileURL.pathComponents
        guard parts.count > folder.count, Array(parts.prefix(folder.count)) == folder else { return nil }
        return parts.dropFirst(folder.count).joined(separator: "/")
    }

    /// The file this address may show, or nil. Nothing is read here; the caller reads the file only when this answers.
    static func file(for url: URL, root: URL) -> URL? {
        guard url.scheme == scheme, url.host == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.query == nil, components.fragment == nil else { return nil }
        let encodedParts = components.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard encodedParts.count >= 3, encodedParts[0].isEmpty else { return nil }
        var parts: [String] = []
        for encoded in encodedParts.dropFirst() {
            guard let decoded = encoded.removingPercentEncoding, isPlainComponent(decoded) else { return nil }
            parts.append(decoded)
        }
        let session = parts[0]
        let relative = Array(parts.dropFirst())
        guard !session.hasPrefix("."), allowedFolders.contains(relative[0]), relative.count >= 2,
              let last = relative.last, allowedExtensions.contains((last as NSString).pathExtension.lowercased()) else { return nil }

        let sessionFolder = root.appendingPathComponent(session, isDirectory: true)
        var candidate = sessionFolder
        for part in relative { candidate.appendPathComponent(part) }

        let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let resolvedFolder = sessionFolder.resolvingSymlinksInPath().standardizedFileURL
        let resolvedCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedFolder.deletingLastPathComponent().path == resolvedRoot.path,
              resolvedCandidate.path.hasPrefix(resolvedFolder.path + "/"),
              allowedFolders.contains(where: { resolvedCandidate.path.hasPrefix(resolvedFolder.path + "/" + $0 + "/") }),
              allowedExtensions.contains(resolvedCandidate.pathExtension.lowercased()) else { return nil }

        guard let values = try? resolvedCandidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= maxBytes else { return nil }
        return resolvedCandidate
    }

    /// One piece of a path: not empty, not "." or "..", and no slash, backslash or NUL (so a decoded %2F cannot sneak in).
    private static func isPlainComponent(_ text: String) -> Bool {
        !text.isEmpty && text != "." && text != ".."
            && !text.contains("/") && !text.contains("\\") && !text.contains("\0")
    }

    static func mimeType(of file: URL) -> String {
        file.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
    }
}

/// Answers `pointroo-image://` requests from the web view. Every request goes through WebImages.file first.
final class WebImageHandler: NSObject, WKURLSchemeHandler {
    private let root: URL

    init(root: URL = Paths.root) { self.root = root }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let file = WebImages.file(for: url, root: root),
              let data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let response = URLResponse(url: url, mimeType: WebImages.mimeType(of: file), expectedContentLength: data.count, textEncodingName: nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
