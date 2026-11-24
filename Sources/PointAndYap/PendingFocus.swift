import Foundation

/// The "show this item" request for the kit main window. If its page is loaded the event goes out now; if not (the app was just
/// opened by a pointroo:// link), the id is kept and goes out once, when the page has loaded. A newer request replaces an older
/// waiting one. Pure: no web view, no timers.
struct PendingFocus: Equatable {
    private(set) var waitingId: String?

    /// The id to send now, or nil when it is kept for later.
    mutating func request(_ id: String, pageReady: Bool) -> String? {
        if pageReady {
            waitingId = nil
            return id
        }
        waitingId = id
        return nil
    }

    /// The page has loaded: the kept id (once), or nil when nothing waits.
    mutating func pageBecameReady() -> String? {
        let id = waitingId
        waitingId = nil
        return id
    }

    /// The item.focus event the page listens for.
    static func event(id: String) -> WebEvents.Event {
        (name: "item.focus", data: ["id": id])
    }
}
