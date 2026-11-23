import Foundation

/// The line between the web screens (the kit app in a web view) and the app. Plain request in, plain reply out, no web view needed.
///
/// The page sends one JSON message per call: `window.webkit.messageHandlers.pointroo.postMessage({id, method, params})`.
///   id      a number or a string the page picks. It comes back unchanged in the reply.
///   method  one name from the table below.
///   params  an object (may be left out).
///
/// The app answers by running `window.pointroo.reply(<id>, <json>)` in the page, where json is
///   `{"result": ...}` when it worked, or `{"error": {"code": "...", "message": "..."}}` when it did not.
/// The app can also tell the page about something with `window.pointroo.emit(<name>, <json data>)`.
///
/// Error codes: bad_request (not valid JSON, or no method), unknown_method, bad_params, not_found, not_available, refused.
///
/// Methods
///   items.list      params {status?: "open" | "in_progress" | "done"}   (no status = every item)
///                   result {items: [Item]}
///   items.get       params {id: string}
///                   result {item: Item}   error not_found when there is no such item
///   items.reroute   params {id: string, project: string}
///                   error not_available for now ("not available yet")
///   settings.get    params {key?: string}
///                   result {key, value} for one key, or {values: {key: value}} for all allowed keys
///   settings.set    params {key: string, value: bool | string}
///                   result {key, value}   error refused when the key is not in the allowed list, bad_params when the value has the wrong kind
///
/// Item: {id, session, n, title, body, crops: [path], status, at?: ISO date, by?, note?, project?, routeHow?}
///
/// Settings keys: sounds, doubleControl, escCancels, redactSecrets, connectAgents, showNoSpeech (all bool);
/// locale (string, one of the ids in Prefs.languages).
final class WebBridge {
    struct Request {
        var id: Any
        var method: String
        var params: [String: Any]
    }

    struct Failure: Error {
        var code: String
        var message: String
    }

    typealias Handler = (WebBridge, [String: Any]) throws -> Any

    /// A settings key the page may read and write, with its kind and what it is when never set.
    enum SettingKind {
        case flag(defaultValue: Bool)
        case choice(allowed: [String], defaultValue: String)
    }

    static let allowedSettings: [(key: String, kind: SettingKind)] = [
        ("sounds", .flag(defaultValue: true)),
        ("doubleControl", .flag(defaultValue: true)),
        ("escCancels", .flag(defaultValue: true)),
        ("redactSecrets", .flag(defaultValue: true)),
        ("connectAgents", .flag(defaultValue: false)),
        ("showNoSpeech", .flag(defaultValue: false)),
        ("locale", .choice(allowed: Prefs.languages.map(\.id), defaultValue: "")),
    ]

    /// The whitelist. A method that is not here is an error.
    static let methods: [String: Handler] = [
        "items.list": { bridge, params in try bridge.itemsList(params) },
        "items.get": { bridge, params in try bridge.itemsGet(params) },
        "items.reroute": { _, _ in throw Failure(code: "not_available", message: "not available yet") },
        "settings.get": { bridge, params in try bridge.settingsGet(params) },
        "settings.set": { bridge, params in try bridge.settingsSet(params) },
    ]

    private let defaults: UserDefaults
    private let loadItems: () -> [Item]

    init(defaults: UserDefaults = .standard, loadItems: @escaping () -> [Item] = { Items.all() }) {
        self.defaults = defaults
        self.loadItems = loadItems
    }

    /// Takes what the page posted (a dictionary or a JSON string) and returns the script to run in the page.
    func handle(message: Any) -> String {
        guard let request = Self.decode(message) else {
            return Self.replyScript(id: NSNull(), outcome: .failure(Failure(code: "bad_request", message: "Not a request with an id and a method.")))
        }
        guard let handler = Self.methods[request.method] else {
            return Self.replyScript(id: request.id, outcome: .failure(Failure(code: "unknown_method", message: "Unknown method \(request.method).")))
        }
        do {
            return Self.replyScript(id: request.id, outcome: .success(try handler(self, request.params)))
        } catch let failure as Failure {
            return Self.replyScript(id: request.id, outcome: .failure(failure))
        } catch {
            return Self.replyScript(id: request.id, outcome: .failure(Failure(code: "bad_request", message: "\(error)")))
        }
    }

    static func decode(_ message: Any) -> Request? {
        var object: [String: Any]?
        if let dictionary = message as? [String: Any] {
            object = dictionary
        } else if let text = message as? String, let data = text.data(using: .utf8) {
            object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
        guard let object, let method = object["method"] as? String, !method.isEmpty else { return nil }
        guard let id = object["id"], id is String || id is NSNumber else { return nil }
        return Request(id: id, method: method, params: object["params"] as? [String: Any] ?? [:])
    }

    static func replyScript(id: Any, outcome: Result<Any, Failure>) -> String {
        let payload: [String: Any]
        switch outcome {
        case .success(let value): payload = ["result": value]
        case .failure(let failure): payload = ["error": ["code": failure.code, "message": failure.message]]
        }
        return "window.pointroo.reply(\(json(id)), \(json(payload)))"
    }

    static func emitScript(name: String, data: Any) -> String {
        "window.pointroo.emit(\(json(name)), \(json(data)))"
    }

    /// JSON text that is safe to put inside a script: made by JSONSerialization, never by joining strings, and with the
    /// characters that can end a script or a JavaScript string early written as escapes.
    static func json(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: [value]),
              let wrapped = String(data: data, encoding: .utf8) else { return "null" }
        let text = String(wrapped.dropFirst().dropLast())
        return text
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    private func itemsList(_ params: [String: Any]) throws -> Any {
        var items = loadItems()
        if let status = params["status"] {
            guard let wanted = status as? String, ["open", "in_progress", "done"].contains(wanted) else {
                throw Failure(code: "bad_params", message: "status must be open, in_progress or done.")
            }
            items = items.filter { $0.status == wanted }
        }
        return ["items": items.map(Self.dictionary)]
    }

    private func itemsGet(_ params: [String: Any]) throws -> Any {
        guard let id = params["id"] as? String, !id.isEmpty else { throw Failure(code: "bad_params", message: "id is needed.") }
        guard let item = loadItems().first(where: { $0.id == id }) else { throw Failure(code: "not_found", message: "No item \(id).") }
        return ["item": Self.dictionary(item)]
    }

    private func settingsGet(_ params: [String: Any]) throws -> Any {
        if let key = params["key"] {
            guard let name = key as? String, let kind = Self.kind(of: name) else { throw Failure(code: "refused", message: "That setting cannot be read.") }
            return ["key": name, "value": value(name, kind)]
        }
        var values: [String: Any] = [:]
        for entry in Self.allowedSettings { values[entry.key] = value(entry.key, entry.kind) }
        return ["values": values]
    }

    private func settingsSet(_ params: [String: Any]) throws -> Any {
        guard let name = params["key"] as? String, let kind = Self.kind(of: name) else {
            throw Failure(code: "refused", message: "That setting cannot be changed.")
        }
        switch kind {
        case .flag:
            guard let number = params["value"] as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw Failure(code: "bad_params", message: "\(name) is on or off (true or false).")
            }
            defaults.set(number.boolValue, forKey: name)
        case .choice(let allowed, _):
            guard let text = params["value"] as? String, allowed.contains(text) else {
                throw Failure(code: "bad_params", message: "\(name) must be one of the known values.")
            }
            defaults.set(text, forKey: name)
        }
        return ["key": name, "value": value(name, kind)]
    }

    private static func kind(of key: String) -> SettingKind? {
        allowedSettings.first { $0.key == key }?.kind
    }

    private func value(_ key: String, _ kind: SettingKind) -> Any {
        switch kind {
        case .flag(let defaultValue): return defaults.object(forKey: key) as? Bool ?? defaultValue
        case .choice(_, let defaultValue): return defaults.string(forKey: key) ?? defaultValue
        }
    }

    static func dictionary(_ item: Item) -> [String: Any] {
        var out: [String: Any] = [
            "id": item.id, "session": item.session, "n": item.n, "title": item.title, "body": item.body,
            "crops": item.crops.map(\.path), "status": item.status,
        ]
        if let at = item.at { out["at"] = ISO8601DateFormatter().string(from: at) }
        if let by = item.by { out["by"] = by }
        if let note = item.note { out["note"] = note }
        if let project = item.project { out["project"] = project }
        if let how = item.routeHow { out["routeHow"] = how }
        return out
    }
}
