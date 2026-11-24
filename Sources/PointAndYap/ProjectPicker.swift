import AppKit
import SwiftUI

/// A small floating list of the live projects after a recording that no rule could route: 1-9 or a click picks, Esc skips.
@MainActor
enum ProjectPicker {
    private static var panel: PickerHandle?
    private static var waiting: CheckedContinuation<Project?, Never>?

    /// How long the picker waits before it skips by itself.
    static let timeoutSeconds = 60

    /// Opens the window for the choices and calls the closure with the answer (a click or a key). Tests replace it so no window opens.
    static var makePanel: ([Project], @escaping @MainActor (Project?) -> Void) -> PickerHandle = ProjectPicker.makeRealPanel

    /// Set by the app: when the kitFloating setting is on it shows the kit picker panel and returns its handle; otherwise it returns nil
    /// and the SwiftUI picker opens as before. The page answers through the bridge (picker.pick, picker.skip); the keys go to answerKey.
    static var makeKitPanel: (([Project]) -> PickerHandle?)?

    /// Sleeps this many seconds before the picker skips by itself. Tests replace it so they do not wait.
    static var pause: (Int) async -> Void = { seconds in
        try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
    }

    /// The time the picker uses for its countdown. Tests replace it.
    static var clock: () -> Date = { Date() }

    /// What the open picker shows, for the web bridge. Nil when no picker is open.
    private static var open: (choices: [Project], session: String?, suggested: String?, openedAt: Date)?

    static func ask(_ projects: [Project], session: String? = nil, suggested: String? = nil) async -> Project? {
        let choices = Array(projects.prefix(9))
        return await withCheckedContinuation { continuation in
            MainActor.assumeIsolated { show(choices, continuation, session: session, suggested: suggested) }
        }
    }

    /// The open picker as the bridge reports it (choices in number-key order), or nil when none is open.
    static func snapshot(now givenNow: Date? = nil) -> PickerSnapshot? {
        let now = givenNow ?? clock()
        guard waiting != nil, let open else { return nil }
        let choices = open.choices.enumerated().map { index, project in
            PickerSnapshot.Choice(name: project.name, path: project.path, key: index + 1,
                                  suggested: open.suggested.map { Router.samePath($0, project.path) } ?? false)
        }
        let left = timeoutSeconds - Int(now.timeIntervalSince(open.openedAt))
        return PickerSnapshot(session: open.session, choices: choices, countdown: max(0, left))
    }

    /// The open picker's choice with this folder, or nil.
    static func snapshotProject(path: String) -> Project? {
        guard waiting != nil else { return nil }
        return open?.choices.first { Router.samePath($0.path, path) }
    }

    /// Answers the open picker the same way a click or Esc does. False when no picker is open (so a second answer does nothing).
    @discardableResult
    static func answer(_ project: Project?) -> Bool {
        guard waiting != nil else { return false }
        finish(project)
        return true
    }

    /// What a key press does to the open picker: Esc (key code 53) skips, a digit 1 to 9 picks the project in that place.
    /// True when the key was used (so the panel does not pass it on). False when no picker is open or the key means nothing here.
    @discardableResult
    static func answerKey(keyCode: UInt16, characters: String?) -> Bool {
        guard waiting != nil, let open else { return false }
        if keyCode == 53 { return answer(nil) }
        guard let digit = Int(characters ?? ""), digit >= 1, digit <= open.choices.count else { return false }
        return answer(open.choices[digit - 1])
    }

    private static func finish(_ project: Project?) {
        panel?.close()
        panel = nil
        open = nil
        let continuation = waiting
        waiting = nil
        continuation?.resume(returning: project)
    }

    private static func show(_ choices: [Project], _ continuation: CheckedContinuation<Project?, Never>, session: String?, suggested: String?) {
        waiting = continuation
        open = (choices: choices, session: session, suggested: suggested, openedAt: clock())
        let handle = makePanel(choices) { finish($0) }
        panel = handle
        Task { @MainActor in
            await pause(timeoutSeconds)
            if panel === handle { finish(nil) }
        }
    }

    private static func makeRealPanel(_ choices: [Project], _ done: @escaping @MainActor (Project?) -> Void) -> PickerHandle {
        if let kitHandle = makeKitPanel?(choices) { return kitHandle }
        let host = NSHostingView(rootView: PickerView(projects: choices, pick: { done($0) }))
        let height = CGFloat(choices.count) * 34 + 78
        host.frame = NSRect(x: 0, y: 0, width: 340, height: height)
        let picker = PickerPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        picker.level = .statusBar
        picker.isFloatingPanel = true
        picker.hasShadow = true
        picker.backgroundColor = .clear
        picker.isOpaque = false
        picker.sharingType = .none
        picker.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        picker.appearance = NSAppearance(named: .aqua)
        picker.contentView = host
        picker.onKey = { event in
            if event.keyCode == 53 { done(nil); return }
            if let digit = Int(event.charactersIgnoringModifiers ?? ""), digit >= 1, digit <= choices.count { done(choices[digit - 1]) }
        }
        let frame = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        picker.setFrameOrigin(NSPoint(x: frame.midX - 170, y: frame.maxY - height - 60))
        picker.makeKeyAndOrderFront(nil)
        return PickerHandle(close: { picker.orderOut(nil) })
    }
}

/// What the picker keeps of its window: a way to close it, and an identity the timeout compares.
final class PickerHandle {
    let close: () -> Void

    init(close: @escaping () -> Void) {
        self.close = close
    }
}

final class PickerPanel: NSPanel {
    var onKey: (@MainActor (NSEvent) -> Void)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) { onKey?(event) }
}

struct PickerView: View {
    var projects: [Project]
    var pick: @MainActor (Project?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Which project?").font(.geist(13, .semibold)).foregroundStyle(Ink.primary)
            ForEach(Array(projects.enumerated()), id: \.offset) { index, project in
                Button { pick(project) } label: {
                    HStack {
                        Text("\(index + 1)").font(.geistMono(12)).foregroundStyle(Ink.muted).frame(width: 18)
                        Text(project.name).font(.geist(13)).foregroundStyle(Ink.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 8).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Ink.field))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("Press a number, or Esc to skip").font(.geist(11)).foregroundStyle(Ink.faint)
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Ink.line, lineWidth: 1))
    }
}
