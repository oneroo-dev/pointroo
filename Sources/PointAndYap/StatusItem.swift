import AppKit

struct QueueCounts: Equatable {
    var open: Int
    var working: Int
    var done: Int
}

/// Pure helpers for the menu bar status and for noticing that an agent finished an item.
enum QueueStatus {
    static func counts(_ items: [Item]) -> QueueCounts {
        QueueCounts(open: items.filter { $0.status == "open" }.count,
                    working: items.filter { $0.status == "in_progress" }.count,
                    done: items.filter { $0.status == "done" }.count)
    }

    /// "1 working, 2 waiting"; empty when nothing is open or working.
    static func statusTitle(_ counts: QueueCounts) -> String {
        var parts: [String] = []
        if counts.working > 0 { parts.append("\(counts.working) working") }
        if counts.open > 0 { parts.append("\(counts.open) waiting") }
        return parts.joined(separator: ", ")
    }

    static func statusByID(_ items: [Item]) -> [String: String] {
        Dictionary(items.map { ($0.id, $0.status) }, uniquingKeysWith: { first, _ in first })
    }

    /// Items that were not done at the last look and are done now, by an agent. Items the user marked done never count.
    /// An item that was not known before is not counted, so the first look (empty `before`) only records.
    static func newlyDone(before: [String: String], items: [Item]) -> [Item] {
        items.filter { item in
            guard item.status == "done", item.by != "you", let earlier = before[item.id] else { return false }
            return earlier != "done"
        }
    }

    /// A value that changes when any session folder or state file changes, so an unchanged queue is not scanned again.
    static func signature() -> Date? {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        var newest = (try? Paths.root.resourceValues(forKeys: Set(keys)))?.contentModificationDate
        for dir in (try? manager.contentsOfDirectory(at: Paths.root, includingPropertiesForKeys: keys)) ?? [] {
            for url in [dir, Items.stateURL(dir)] {
                guard let date = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate else { continue }
                if newest == nil || date > newest! { newest = date }
            }
        }
        return newest
    }
}

/// The menu bar item: the queue at a glance, and a way back to the window while it is hidden.
@MainActor
final class StatusItem: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let openWindow: () -> Void
    private let quit: () -> Void

    init(openWindow: @escaping () -> Void, quit: @escaping () -> Void) {
        self.openWindow = openWindow
        self.quit = quit
        super.init()
        item.button?.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: "Pointroo")
        item.button?.imagePosition = .imageLeading
        update(QueueCounts(open: 0, working: 0, done: 0), active: [])
    }

    func update(_ counts: QueueCounts, active: [Item]) {
        item.button?.title = QueueStatus.statusTitle(counts)
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Pointroo", action: #selector(openPressed), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        if !active.isEmpty {
            menu.addItem(.separator())
            for entry in active.prefix(12) {
                let words = entry.title.split(separator: " ").prefix(6).joined(separator: " ")
                let line = NSMenuItem(title: "\(entry.status == "in_progress" ? "Working" : "Waiting"): \(words)", action: nil, keyEquivalent: "")
                line.isEnabled = false
                menu.addItem(line)
            }
        }
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Pointroo", action: #selector(quitPressed), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
    }

    @objc private func openPressed() { openWindow() }
    @objc private func quitPressed() { quit() }
}
