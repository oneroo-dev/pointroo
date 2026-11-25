# Pointroo UI inventory (today's SwiftUI app, 2026-11-23)

Read from the code at commit 7e50eef (`Sources/PointAndYap`). Everything the user sees or touches is listed, so the redesign loses nothing. "NEW" marks things in the redesign plan that the app does not have yet.

Facts that shape every screen:
- Pointroo records the screen while the user points and talks. One recording = one **item**. An item has: what was said, the elements pointed at, crops (cropped screenshots), full frames, a project it was routed to, a status, who took it, a one-line note.
- Status: `open` (shown "To fix"), `in_progress` (an agent works on it, shows the agent name), `done` (by an agent or by "you"). An in-progress item with no finish after 2 hours goes back to open.
- Route ("how" it was sent to a project): `said` (project name spoken), `screen` (the window or host pointed at), `followup` (follows the item an agent just finished), `only` (one project folder exists), `picked` (user picked in the picker). No route = "not routed".
- Look today: Geist font, near-black ink on white, one gold dot accent, black 8pt buttons. Always light (window is forced to the light theme). Window is one fixed 400 x 590 popover-like window; no resize.
- Sessions list shows the newest 20 with speech. Recordings with no speech are hidden unless a setting turns them on.
- Data lives in `~/Pointroo/sessions/<date_time>/` (events.json, transcript.json, state.json, route.json, frames/, crops/). Sounds: start, done (soft tones).

## 1. Main window (`Views.swift` MainView)

One window, 400 x 590, no title text (transparent title bar, draggable by background), centered, position remembered. It shows ONE of three things at a time: Settings, the first-run agent question, or the main screen. Closing the window does not quit (menu bar item + Dock icon bring it back). While recording the window hides.

Main screen, top to bottom:
1. Header row: app icon 30px, name "Pointroo", tagline "Show, don't type."; right side a gear button (tooltip "Settings (Cmd+,)").
2. Permission rows (only when any of the three is missing): card with rows Microphone, Screen recording, Accessibility. Each row: name, then a check mark if allowed, else an "Allow" button. Allowing screen recording or accessibility arms an app relaunch (macOS needs it) and opens the System Settings pane.
3. Update-ready bar (only when a new version is downloaded): gold dot, "Pointroo <version> is ready", "Restart" button.
4. Welcome card (first run, only when all permissions are allowed and idle): 352 x 220 looping muted video of how it works (9 s), caption "Control twice, point and talk, Control twice.", "Got it" button. "How it works" link brings it back later.
5. Primary button, full width, 44px: "Start recording" with a red dot. While processing: spinner + "Writing instructions..." (button disabled). Disabled and faded to 40% when a permission is missing.
6. Hint line under it: "Or press Control twice." (first run: "Or press Control twice. Rest the cursor on what you mean."), plus an underlined "How it works" link (hidden while the welcome card is on).
7. "Recent" list (section label). Empty: "Nothing recorded yet". Otherwise rows, 50px, divider lines:
   - Left: title (first ~9 words said, one line, truncated; "No speech" or "Processing..." as fallbacks) and under it "d MMM, HH:mm . N s".
   - Right at rest: status pill: "To fix" (gold), "In progress . <agent>" (grey), "Done" (green). No pill when the recording has nothing said.
   - On hover the pill is replaced by: folder icon button (tooltip "Open the folder", opens Finder), and "Done" (dark) / "Reopen" button (only when the item has a status).
   - Click the row: copies the 2-line pointer text for an agent ("New in Pointroo: ..."), toast "Copied". Tooltip: "Note: <agent note>" or "Click to copy it for an agent".
8. Toast: dark capsule at the bottom, 2 s (messages below). The MCP busy-port message shows 8 s.

Toast messages today: "Couldn't start: <error>", "Sent to <project>", "Copied. Paste it into your agent", "Copied", "Not sent - kept in the queue", "Open again", "Marked done", "Connected", and the MCP port-busy text (see Settings).

There is NO item detail view today (no crops, elements, frames, transcript view). The only ways to see an item are the folder in Finder or an agent reading it. NEW: item detail (said text, crops, elements, frames), queue grouped by project, filters.

## 2. First-run agent question (`AgentsQuestion`)

Replaces the main window until answered. App title, then "Connect your coding agents?", subtext "They get a local MCP server and a skill to read your recordings. Each config is backed up first." A card listing the agents found on this Mac (e.g. Claude Code, Codex, Cursor), one per row. Buttons: "Connect" (primary), "Skip". Footnote "You can change this in Settings." Nothing in any agent config changes before "Connect".

## 3. Settings (`Settings.swift`), same 400 x 590 window, replaces the main screen

Header: "Back" (chevron) button, centered title "Settings". Cmd+, opens it. Groups (cards), each row has a title and a one-line hint:

Recording
- Sounds: "A soft sound at start and when it is copied" (switch, default on)
- Control twice: "Starts and stops a recording from any app" (switch, default on)
- Esc cancels: "Stops and moves the recording to the Trash" (switch, default on)
- Show recordings without speech (switch, default off)
- Speech language: "Transcribed on this Mac" (menu): Same as the Mac, English, German, French, Spanish, Italian, Portuguese, Dutch, Japanese, Chinese

Coding agents
- Connect automatically: "Adds the MCP and skill to your coding agents" (switch, default off until the first-run yes)
- Agent status line: "No agents found" or "Claude Code check   Codex dash ..." (check = connected, dash = not) and a "Connect now" button (runs the install, refreshes the line)
- MCP status line (small text, can wrap to 2+ lines): "Shared MCP server: not started" | "Shared MCP server: running on 127.0.0.1:6742" | busy: "Port 6742 is in use by another program. Quit it, or pick another port: defaults write dev.oneroodev.pointroo mcpPort <n>, then restart Pointroo." | other: "The shared MCP server could not use port N (error E)." / "could not listen on port N (error E)."
  Default port 6742, set by `defaults write dev.oneroodev.pointroo mcpPort <n>`. A token file is kept in Application Support (not shown).

General
- Open at login (switch; falls back to the real state if macOS refuses)
- Version <x.y.z>
- Recordings: "Show in Finder" button (opens ~/Pointroo/sessions)
- Footer: "Based on Point and Yap by Marc Maurer (MIT)"

NEW in plan, not in code today: "Blur secrets in screenshots" switch, follow-up window setting, a port field and permission status inside Settings.

## 4. Recording pill (`PillView`, floating panel in `App.swift`)

Borderless floating panel, 200 x 40, top center of the main screen, above all windows, on all Spaces, movable by dragging, never captured in screenshots (sharingType none), clicks on it are not counted as points. Contents: pulsing red dot, elapsed time m:ss (mono), a small "esc" text button (tooltip "Cancel and keep nothing"), a dark "Stop" button with the keys hint (control control). While recording: main window hidden, focus returns to the app that was in front, done banners wait.

## 5. Project picker HUD (`ProjectPicker.swift`)

Shown after a recording no rule could route, when 2+ agent sessions are live. Floating panel 340 wide, top center, key window (takes keyboard). Title "Which project?"; up to 9 rows, each: number (mono) 1-9, project name; hint "Press a number, or Esc to skip". Number key or click picks; Esc skips ("Not sent - kept in the queue"); times out after 60 s (same as skip). A pick teaches the router (learned aliases) and sets route how = `picked`; toast "Sent to <project>".

## 6. Done banner (`DoneBanner.swift`)

Floating panel, 320 x 64, top right, above all windows, not in screenshots. Appears when an AGENT finishes an item (never when the user marks done) and the window is hidden or not. Gold dot + "<project> is done" (13px semibold), under it the agent's note (or the item title) up to 2 lines. Click: opens the main window. Shows 4 s, one at a time, queued; waits while recording. NEW: "before | Screen now" thumbnails, Reply, click opens the recording.

## 7. Menu bar item (`StatusItem.swift`)

Icon (cursor click symbol) plus a title with counts: "1 working, 2 waiting" (empty when nothing). Dropdown: "Open Pointroo"; then, if any, a separator and up to 12 disabled lines "Working: <first 6 words>" / "Waiting: <first 6 words>"; separator; "Quit Pointroo". Counts refresh every 5 s even with the window hidden.

## 8. App menu and keys

Settings... (Cmd+,), Hide Pointroo (Cmd+H), Quit Pointroo (Cmd+Q), Copy, Select All, Close (Cmd+W), Minimize (Cmd+M). Global: double Control starts/stops a recording; Esc while recording cancels (both can be turned off in Settings). Dock icon click reopens the window (not while recording).

## 9. Not UI, but the screens depend on it

- MCP tools agents use: get_open_items (takes items in progress), wait_for_next (listen mode), mark_done (with a one-line note), start_items, release_items (give back with a reason), list_items (open/in_progress/done), list_sessions, get_session (timeline + crops), get_frame. CLI fallback: `Pointroo --items`, `--done <id> --note "..."`. Claude Code Stop hook: `--hook-stop`.
- Item fields the UI can show: id (`<session>#<n>`), title, body (said text with [n] marks where the cursor was; "Pointed at:" lines: kind click/dwell, app, window, url, element description, ancestors path), crops, frames (file, time, reason start/point/click/interval), project, route how, status, by, at, note, duration, number of points.
- Permissions: Microphone, Screen recording, Accessibility. App relaunches after a grant.
- Update: downloads a new version in the background, then offers Restart.
- Offscreen design check exists today (`Pointroo --render-ui <dir>`): window, welcome, rows, window-access, settings, agents, pill. Useful as the list of states that were designed before.

## States the redesign must cover (from the plan and the code)

Main: empty (nothing recorded), loading/processing ("Writing instructions..."), permission missing (each of three), update ready, welcome (first run), agents question, toast, many items, long titles, no-speech rows, item open / in progress / done, not routed.
Settings: all rows above, MCP running / not started / port busy / error, agents found / none, permission states.
Panels: done banner (single, queued), question panel (NEW), picker (2 to 9 projects), recording pill (recording; cancel; stop), menu bar (idle, counts, list).

## App (src/)

The real main window, built from the same parts as the approved mockups (2026-11-24, W1).
- `src/parts/` holds the shared screen parts: MainWindow, ItemList, ItemDetail, ProjectTiles, QuestionControls, StatusBanner, AppGlyph, words.ts, projects.ts, types.ts. They take data as props and raise events (select, send, sendAll, move, done, trash, reopen, copy, reveal, answer, undo and more). The mockups import them from here and pass sample data (`mockups/parts/MainWindow.vue` is only a review frame with a scenario switch).
- `src/bridge.ts` is `call(method, params)` and `on(event, handler)` over `window.webkit.messageHandlers.pointroo` and `window.pointroo.reply/emit`. A reply with an error rejects with a `BridgeError` (code, message). In a plain browser `src/fakeBridge.ts` answers from the mockup sample data.
- `src/types.ts` has the shapes of every bridge reply and event (WebBridge.swift). `src/viewModel.ts` turns them into what the parts draw.
- `src/store.ts` holds items (items.list grouped by project), projects, questions, status and the picks (tab, project filter, selected item, toast). It asks again on items.changed and questions.changed, takes status.changed and recording.changed as they come.
- `src/App.vue` wires the store to MainWindow and handles the keys: 1 to 5 send to a tile, D done, Delete trash, Enter open the first item, Cmd+1 to 9 project, Esc closes the detail when narrow. A press on the bar's empty background calls `window.startDrag`.
- Send and move show a 5 s toast with Undo (reroute back, or `items.unroute` for a first send). Done, Open again, Trash and Copy call the W2 methods; a `not_available` answer shows as a toast.
- Build: `npm run dev` (browser, port 5191, fake bridge), `npm run build` (writes `dist/`, loaded from file://), `npm run typecheck`. `npm run mockups` still builds the mockups.
