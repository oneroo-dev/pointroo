import AppKit
import SwiftUI

@main
struct Main {
    static func main() {
        let args = CommandLine.arguments
        // The queue from a shell, for agents without the MCP:
        //   Pointroo --items            open and in-progress items
        //   Pointroo --done <id>... [--note "what changed"]
        if args.contains("--items") || args.contains("--done") { QueueCLI.run(args); return }
        // Claude Code Stop hook: Pointroo --hook-stop (JSON on stdin)
        if args.contains("--hook-stop") { HookStop.run(); return }
        // Local MCP server for coding agents: Pointroo --mcp
        if args.contains("--mcp") { MCPBridge.run(); return }
        // Headless: Pointroo --process <session dir>
        if let i = args.firstIndex(of: "--process"), i + 1 < args.count {
            let dir = URL(fileURLWithPath: args[i + 1])
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                let text = await Process.run(dir: dir) { print("pointroo: \($0)") }
                print(text)
                done.signal()
            }
            done.wait()
            return
        }
        // Offscreen design check: Pointroo --render-ui <dir>
        if let i = args.firstIndex(of: "--render-ui"), i + 1 < args.count {
            MainActor.assumeIsolated { RenderUI.run(to: URL(fileURLWithPath: args[i + 1])) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let state = AppState()
    private var window: NSWindow!
    private var kitHost: WebHost?
    private var windowSwapper: MainWindowSwapper?
    private var pill: NSPanel!
    private var previousApp: NSRunningApplication?
    private var doubleControl: DoubleControl?
    private var statusItem: StatusItem?
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.mainMenu = makeMenu()
        let firstChoice = Self.wantedWindowChoice()
        buildWindow(firstChoice)
        let swapper = MainWindowSwapper(shown: firstChoice, wanted: { Self.wantedWindowChoice() },
                                        swap: { [weak self] choice in self?.swapWindow(to: choice) })
        windowSwapper = swapper
        // The kitWindow setting is read again whenever UserDefaults changes, so the window switches at once.
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            // Later, not inside the write: the switch in the web Settings screen must finish its bridge call before its web view moves.
            DispatchQueue.main.async { MainActor.assumeIsolated { _ = swapper.settingsMayHaveChanged() } }
        }

        pill = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40), styleMask: [.borderless, .nonactivatingPanel],
                       backing: .buffered, defer: false)
        pill.level = .statusBar
        pill.isFloatingPanel = true
        pill.hasShadow = true
        pill.backgroundColor = .clear
        pill.isOpaque = false
        pill.isMovableByWindowBackground = true
        pill.sharingType = .none                  // never in a screenshot
        pill.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        pill.appearance = NSAppearance(named: .aqua)
        let host = NSHostingView(rootView: PillView(state: state))
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 40)
        pill.contentView = host

        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { if let app, app != .current { self?.previousApp = app } }
        }
        MCPListener.startAtLaunch { [weak self] in self?.state.toast = $0 }
        state.ownUI = { [weak self] in self?.pillRect() }
        state.onRecordingChanged = { [weak self] on in self?.recording(on) }
        // Agent configs are only touched after a yes: the first launch asks, later launches follow the switch.
        if AgentInstall.installed {
            if AgentInstall.needsAsking() { state.askAgents = AgentInstall.status().map(\.name) }
            else { DispatchQueue.global(qos: .utility).async { AgentInstall.run() } }
        }
        // Keep the 5 s timer (and the agents' listener) running while the window is hidden.
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Watching the queue for finished items")
        statusItem = StatusItem(openWindow: { [weak self] in self?.showWindow() }, quit: { [weak self] in self?.quitByUser() })
        state.onQueue = { [weak self] counts, active in self?.statusItem?.update(counts, active: active) }
        state.wireListenWindow()
        state.onDone = { [weak self] item, project in
            Task {
                let notice = await AfterShot.notice(item: item, project: project)
                DoneBanner.shared.show(project: notice.project, note: notice.note, before: notice.before, after: notice.after,
                                       session: notice.session) { self?.showWindow() }
            }
        }
        // Agents mark items done from their own processes: look again, with the window hidden too (the scan is off the main actor).
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.state.pollQueue()
                if self.window.isVisible, self.state.phase == .idle { self.state.loadSessions() }
            }
        }
        state.pollQueue()
        state.refreshAccess()
        doubleControl = DoubleControl(fire: { [weak self] in if Prefs.doubleControl { self?.state.toggle() } },
                                      escape: { [weak self] in if Prefs.escCancels { self?.state.cancel() } },
                                      holdStart: { [weak self] in
                                          // Holding Control during a listen window takes it over: the release then stops it.
                                          if self?.state.takeOverListening() == true { return true }
                                          guard let state = self?.state, state.phase == .idle, state.allowed else { return false }
                                          state.start()
                                          if case .recording = state.phase { return true }
                                          return false
                                      },
                                      holdEnd: { [weak self] in self?.state.stop() })
        state.loadSessions()
        Updater.shared.start(state: state)
        Heartbeat.start()
        bringWindowToFront()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The kit window is used when the kitWindow setting is on (it is on unless the user turned it off) and the built screens
    /// are in the app (Contents/Resources/ui/index.html), or a dev address is set. Read at launch and again on every settings change.
    private static func wantedWindowChoice() -> MainWindowChoice {
        MainWindowChoice.decide(kitWindow: UserDefaults.standard.object(forKey: "kitWindow") as? Bool ?? true,
                                uiAvailable: uiAvailable)
    }

    private static var uiAvailable: Bool {
        if WebHost.devURL(from: Prefs.webDevURL) != nil { return true }
        guard let folder = WebHost.bundleFolder else { return false }
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.html").path)
    }

    private func buildWindow(_ choice: MainWindowChoice) {
        switch choice {
        case .kit: makeKitWindow()
        case .classic: makeClassicWindow()
        }
    }

    /// Replaces the main window with the other kind, keeping the top-left corner where it was. A shown window is replaced by a shown
    /// one; a hidden window by a hidden one, so the next show already has the right kind. The old window loses its delegate first,
    /// so closing it does not stop the events of the new one.
    private func swapWindow(to choice: MainWindowChoice) {
        let oldWindow: NSWindow = window
        let wasVisible = oldWindow.isVisible
        let topLeft = NSPoint(x: oldWindow.frame.minX, y: oldWindow.frame.maxY)
        kitHost?.stopEvents()
        oldWindow.delegate = nil
        buildWindow(choice)
        window.setFrameTopLeftPoint(topLeft)
        oldWindow.orderOut(nil)
        oldWindow.contentView = nil
        oldWindow.close()
        if wasVisible { bringWindowToFront() }
    }

    /// The old SwiftUI main window.
    private func makeClassicWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 590),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .white
        window.appearance = NSAppearance(named: .aqua)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: MainView(state: state))
        window.center()
        window.setFrameAutosaveName("PointMain")
    }

    /// The main window made of the kit screens (a web view). The traffic lights stay native over the page.
    /// The bridge runs on the main actor (WebHost hands each page message to it there), so its closures use MainActor.assumeIsolated
    /// to reach AppState. After a change they call loadSessions, so the SwiftUI side and the status item see it too.
    private func makeKitWindow() {
        let state = self.state
        let bridge = WebBridge(
            reroute: { id, project in MainActor.assumeIsolated { state.reroute(id, to: project) } },
            askPermission: { which in
                MainActor.assumeIsolated {
                    switch which {
                    case "microphone": state.askMic()
                    case "screenRecording": state.askScreen()
                    case "accessibility": state.askAX()
                    default: break
                    }
                }
            },
            changeStatus: { id, status, note in
                let outcome = WebBridge.changeItemStatus(id: id, status: status, note: note)
                if outcome == .changed { MainActor.assumeIsolated { state.loadSessions() } }
                return outcome
            },
            unroute: { id in
                let outcome = Items.unroute(id: id)
                if outcome == .unrouted { MainActor.assumeIsolated { state.loadSessions() } }
                return outcome
            },
            startDrag: { [weak self] in MainActor.assumeIsolated { self?.kitHost?.performWindowDrag() } })
        // One WebHost for the life of the app: a swap back to the kit window moves the same web view into the new window.
        let host: WebHost
        if let existing = kitHost {
            host = existing
        } else {
            host = WebHost(bridge: bridge)
            host.load()
            kitHost = host
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Pointroo"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 480, height: 420)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = host.webView
        window.center()
        window.setFrameAutosaveName("PointKitMain")
    }

    /// Shows the main window; the kit window also starts telling its page about changes.
    private func bringWindowToFront() {
        window.makeKeyAndOrderFront(nil)
        if windowSwapper?.shown != .classic { kitHost?.startEvents(state: state) }
    }

    func windowWillClose(_ notification: Notification) {
        kitHost?.stopEvents()
    }

    func applicationDidHide(_ notification: Notification) {
        kitHost?.stopEvents()
    }

    func applicationDidUnhide(_ notification: Notification) {
        if window.isVisible, windowSwapper?.shown != .classic { kitHost?.startEvents(state: state) }
    }

    /// pointroo://item/<id>: show the main window on that item.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where state.handle(url: url) { showWindow() }
    }

    func applicationDidBecomeActive(_ note: Notification) { state.refreshAccess(); state.loadSessions() }

    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if case .recording = state.phase { return false }
        bringWindowToFront()
        return true
    }

    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        bringWindowToFront()
    }

    private func recording(_ on: Bool) {
        DoneBanner.shared.paused = on
        if on {
            window.orderOut(nil)
            kitHost?.stopEvents()
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let f = screen.visibleFrame
            pill.setFrameOrigin(NSPoint(x: f.midX - 100, y: f.maxY - 52))
            pill.orderFrontRegardless()
            // Hand the screen back to the app that was in front before Pointroo.
            previousApp?.activate()
        } else {
            // Stay out of the way: the session is in the list and on the clipboard; the Dock icon opens the window.
            pill.orderOut(nil)
        }
    }

    /// The pill in global top-left coordinates, with a margin.
    private func pillRect() -> CGRect? {
        guard pill.isVisible else { return nil }
        let h = NSScreen.screens.first?.frame.height ?? 0
        let f = pill.frame.insetBy(dx: -12, dy: -12)
        return CGRect(x: f.minX, y: h - f.maxY, width: f.width, height: f.height)
    }

    /// ⌘Q and the menu's Quit: the user's choice, so no reopen.
    @objc private func quitByUser() {
        Relaunch.cancel()
        NSApp.terminate(nil)
    }

    @objc private func openSettings() {
        state.showSettings = true
        bringWindowToFront()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Hide Pointroo", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Pointroo", action: #selector(quitByUser), keyEquivalent: "q")
        quit.target = self
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Window")
        win.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        win.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        winItem.submenu = win
        return main
    }
}
