import AppKit
import SwiftUI

struct BannerNotice: Equatable {
    var project: String
    var note: String
    /// The crop from the recording, the screen when the agent finished, and the recording's folder. All optional; the banner view does not show them yet.
    var before: URL? = nil
    var after: URL? = nil
    var session: URL? = nil
}

/// Waiting banners. One shows at a time; none start while `paused` (recording).
struct BannerQueue {
    private var pending: [BannerNotice] = []
    private var showing = false

    mutating func add(_ notice: BannerNotice) { pending.append(notice) }

    /// The next banner to show, or nil when one is showing, none are waiting, or it is paused.
    mutating func next(paused: Bool) -> BannerNotice? {
        guard !paused, !showing, !pending.isEmpty else { return nil }
        showing = true
        return pending.removeFirst()
    }

    mutating func finished() { showing = false }
}

struct DoneBannerView: View {
    var notice: BannerNotice
    var onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(Ink.gold).frame(width: 8, height: 8)
                    Text("\(notice.project) is done").font(.geist(13, .semibold)).foregroundStyle(Ink.primary)
                }
                Text(notice.note).font(.geist(12)).foregroundStyle(Ink.muted).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(width: 320, height: 64, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Ink.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A small floating notice, top right, for when an agent finishes an item and the window is hidden.
@MainActor
final class DoneBanner {
    static let shared = DoneBanner()

    /// While true (recording), banners wait; they show after it turns false.
    var paused = false { didSet { if !paused { showNext() } } }
    var onClick: (() -> Void)?

    private var queue = BannerQueue()
    private var panel: NSPanel?

    func show(project: String, note: String, before: URL? = nil, after: URL? = nil, session: URL? = nil, onClick: @escaping () -> Void) {
        self.onClick = onClick
        queue.add(BannerNotice(project: project, note: note, before: before, after: after, session: session))
        showNext()
    }

    private func showNext() {
        guard let notice = queue.next(paused: paused) else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: DoneBannerView(notice: notice) { [weak self] in self?.clicked() })
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 64)
        panel.contentView = host
        let frame = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.maxX - 320 - 16, y: frame.maxY - 64 - 12))
        panel.orderFrontRegardless()
        generation += 1
        let mine = generation
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if let self, self.generation == mine { self.finish() }
        }
    }

    /// Counts the banners shown, so an old banner's timer cannot hide a newer one.
    private var generation = 0

    private func finish() {
        generation += 1
        panel?.orderOut(nil)
        queue.finished()
        showNext()
    }

    private func clicked() {
        let action = onClick
        finish()
        action?()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 64), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.sharingType = .none                  // never in a screenshot
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .aqua)
        return panel
    }
}
