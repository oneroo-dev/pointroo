import AppKit
import SwiftUI

/// A small floating list of the live projects after a recording that no rule could route: 1-9 or a click picks, Esc skips.
@MainActor
enum ProjectPicker {
    private static var panel: PickerPanel?
    private static var waiting: CheckedContinuation<Project?, Never>?

    static func ask(_ projects: [Project]) async -> Project? {
        let choices = Array(projects.prefix(9))
        return await withCheckedContinuation { continuation in
            MainActor.assumeIsolated { show(choices, continuation) }
        }
    }

    private static func finish(_ project: Project?) {
        panel?.orderOut(nil)
        panel = nil
        let continuation = waiting
        waiting = nil
        continuation?.resume(returning: project)
    }

    private static func show(_ choices: [Project], _ continuation: CheckedContinuation<Project?, Never>) {
        waiting = continuation
        let host = NSHostingView(rootView: PickerView(projects: choices, pick: { finish($0) }))
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
            if event.keyCode == 53 { finish(nil); return }
            if let digit = Int(event.charactersIgnoringModifiers ?? ""), digit >= 1, digit <= choices.count { finish(choices[digit - 1]) }
        }
        let frame = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        picker.setFrameOrigin(NSPoint(x: frame.midX - 170, y: frame.maxY - height - 60))
        panel = picker
        picker.makeKeyAndOrderFront(nil)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            if panel === picker { finish(nil) }
        }
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
