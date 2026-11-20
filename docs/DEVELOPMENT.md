# Developing Pointroo

Pointroo is a fork of Point and Yap and runs next to it without touching it. The app is `/Applications/Pointroo.app`
(bundle id `dev.oneroodev.pointroo`, binary `Pointroo`; the Swift target is still `PointAndYap`), its MCP server `pointroo`,
its skill `pointroo`, its recordings `~/Pointroo/sessions`, its support folder `~/Library/Application Support/Pointroo`.
It has no update feed. Build and install with `bash scripts/build.sh` (signed with the "Pointroo Dev" certificate if you made it, else ad hoc, unless `CODESIGN_IDENTITY` is set). See "Dev loop" below.
The text below is mostly from the original and still says Point and Yap in places.

1. Open the app and press Start recording. The window steps aside and a small pill with the time and Stop stays on top
   (it is never in the screenshots, and clicks on it are not points).
2. Talk and point: rest the cursor on the thing you mean while you say "this", "here", "that one". Clicks count too.
3. Press Stop. A few seconds later a sound plays and the instructions are on the clipboard. Paste them into Claude Code.
   Recent sessions are listed in the window: click one to copy it again, the folder button opens it.

Each session is kept in `~/PointAndYap/sessions/<date_time>/`: `session.md` (the aligned timeline, no model), `crops/` (the screen at each point, red ring = cursor, yellow box = element), `frames/`, `events.json`,
`transcript.json`, `audio.caf`.

## Dev loop

Ad-hoc builds look like a new app to macOS every time, so Screen Recording and Accessibility had to be granted again after
each build. A stable certificate fixes that, and `dev.sh` rebuilds and relaunches for you.

1. Once: `bash scripts/dev-cert.sh`. It makes a self-signed code-signing certificate "Pointroo Dev" in your login keychain
   (it may ask for your password) and prints the identities. `build.sh` and `dev.sh` use it by themselves when it exists
   and say which signing they used.
2. After the first build signed with "Pointroo Dev", reset and grant the permissions ONE last time
   (`tccutil reset ScreenCapture dev.oneroodev.pointroo`, `tccutil reset Accessibility dev.oneroodev.pointroo`, open the app,
   allow both). After that, rebuilds keep them.
3. Then work with `bash scripts/dev.sh --watch`. It does a debug build, updates `/Applications/Pointroo.app` in place,
   re-signs it and relaunches it, and does so again whenever a file under `Sources/` or `Resources/` changes. A failed build
   prints the error and the running app stays. `bash scripts/dev.sh` does one round. If the app is not installed yet it
   runs `build.sh` once. Neither restarts the app during a recording.

Claude sessions start their own `Pointroo --mcp` process when the session starts, so changes to the MCP server reach a
session only after it restarts or reconnects (`/mcp`). The menu bar app relaunches by itself.

## Fully local

Recording, speech-to-text (Apple's on-device model), the timeline, crops, the queue and the MCP all run on this Mac; nothing
is sent anywhere. Esc while recording cancels it (the session goes to the Trash).

## Settings

- Language of the speech model: `defaults write com.marcmaurer.pointandyap locale en-US` (or `de-DE`, ...). Default: the system's.

## Build

```bash
bash scripts/build.sh
```

Builds with SwiftPM, signs with the Developer ID in `CODESIGN_IDENTITY` (from the environment, else the workspace `.env` or
`POINTANDYAP_ENV=<file>`), hardened runtime, installs `/Applications/Point and Yap.app`. It refuses while a recording runs.

A release: add a `## <version>` section to `CHANGELOG.md`, commit and push, then `bash scripts/release.sh <version>`. It
builds, signs, notarizes and staples the app, builds `PointAndYap.dmg` (signed, notarized, stapled, checked with `spctl`)
and creates a draft GitHub release. Publishing the draft on GitHub turns on the site's Download button.
Keys: `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_KEY_PATH`. Permissions (asked on first launch): Microphone, Screen Recording,
Accessibility.

Reprocess a session headless: `"/Applications/Point and Yap.app/Contents/MacOS/PointAndYap" --process ~/PointAndYap/sessions/<dir>`
(delete `transcript.json` to transcribe again).

- Design check without a screen: `PointAndYap --render-ui <dir>` (window, permissions, rows, Settings, the agents question, pill
  as PNGs). Run the bundle's binary so the icon and fonts load. The README images: `assets/src/` (HTML rendered with
  Chromium, then `cwebp`).

## For agents: the queue

- Each recording is one item: everything said in it, with [n] where the cursor was, and the elements and crops of every
  click or rest of half a second or more. An agent does all of it, then marks it done. (Splitting by pointing or with
  Apple's on-device model was tried on real sessions on 17 Oct 2026 and cut single requests into pieces.) Items are open, in progress (by which agent) or done (`state.json` in the session folder).
- After Stop the clipboard gets two lines ("New in Point and Yap: …" and how to get them). The window shows
  To fix, In progress (by which agent) or Done per recording, refreshes every 5 s, and hovering a row offers Done or Reopen.
- `PointAndYap --mcp` is a local MCP server over stdio, no auth: `get_open_items` (marks the open items in progress by the calling
  agent, oldest first, with crops), `start_items` (specific ids), `list_items` (every item with its state), `mark_done` (ids, note), `release_items` (ids, note: back to the queue), `list_sessions`,
  `get_session`, `get_frame`. An item in progress that no one finished returns after two hours. One lock (`~/PointAndYap/.lock`) keeps
  agents in separate processes from taking the same item.
- The first launch from /Applications asks before connecting (Connect or Skip; `agentsAsked`, `connectAgents`); a Mac
  where Point was already registered counts as a yes. After a yes, each launch registers the MCP with Claude Code (`claude mcp add --scope user`), Codex
  (`~/.codex/config.toml`) and Cursor (`~/.cursor/mcp.json`) when not there yet, and links its skill
  (`Resources/skill/point`) into `~/.claude/skills` and `~/.agents/skills`. Configs are backed up first to
  `~/Library/Application Support/PointAndYap/backups/`. An entry named pointandyap that is not ours is left alone; entries of the earlier name (point) are replaced.
- From a shell, for agents without the MCP: `PointAndYap --items`, `PointAndYap --done <id> --note "what changed"` (`POINTANDYAP_AGENT`
  names the agent).
- Tests against another folder: `POINTANDYAP_SESSIONS=<dir> PointAndYap --mcp`.

## The site

`site/`: pointandyap.com, a Cloudflare Worker with static assets in the maintainer's Cloudflare account. `/api/stats`
reads stars and the DMG release downloads from GitHub (10 min cache); the Download button turns on when a release has a
DMG. Deploy: `cd site && npx wrangler@4 deploy` with the workspace `.env` loaded (and `CLOUDFLARE_ACCOUNT_ID` unset). The
domains are attached as Worker custom domains through the API, not in `wrangler.toml`. until launch (two lines in `worker.js`). Local preview: launch config `pointandyap-site`, port 4261.

## Releasing

1. `bash scripts/release.sh <version>`: builds, notarizes, makes the DMG and a draft GitHub release.
2. `bash scripts/publish.sh <version>`: publishes the release, writes and deploys `site/public/appcast.xml` (signed with
   the update key: `POINTANDYAP_SPARKLE_KEY=<private key file>`, else the login Keychain, account `pointandyap`),
   commits it, and updates the Homebrew cask. Installed copies pick the version up within a few hours.

Automatic: merge a pull request that renames `## Unreleased` in `CHANGELOG.md` to the new version (`## 0.1.5`).
`scripts/auto-release.sh`, run every 15 minutes by a LaunchAgent on the maintainer's Mac
(`com.marcmaurer.pointandyap-release`, its own clone and log in `~/Library/Application Support/PointAndYap-release/`),
sees a changelog version newer than the latest release and runs both steps above, with a notification at the start and
the end. Other merges release nothing. `bash scripts/auto-release.sh --dry-run` says what it would do.

The update key's public half is `SUPublicEDKey` in `Resources/Info.plist`; keep the private half out of the repo and backed
up. Losing it means installed copies can no longer be updated. To test an update locally, serve a feed and set
`defaults write com.marcmaurer.pointandyap updateFeedURL <url>` (the download must still be signed); delete it after.

## Numbers

`node scripts/stats.mjs` prints who comes and from where: GitHub views, visitors, clones, referrers, stars and DMG
downloads, and pointandyap.com's views, visitors, downloads, installer runs and copies in use (from the Worker's
Analytics Engine dataset `pointandyap_events`; needs `CLOUDFLARE_API_TOKEN`). GitHub keeps traffic for 14 days only, so
`node scripts/stats.mjs --snapshot` saves it daily to `~/.pointandyap-stats` (a LaunchAgent can run it).

## Routing to projects

Each `PointAndYap --mcp` process runs in its Claude session's project folder. On `initialize` it writes
`~/Library/Application Support/PointAndYap/live/<pid>.json` (cwd, agent, started, lastSeen), refreshed on tool calls and
removed when stdin closes; readers skip and delete files of dead pids. `projects.json` in the same folder lists known
projects (`name`, `path`, `aliases`, `hosts`, `titles`); live session folders are added by folder name. Set
`POINTANDYAP_SUPPORT` to use another folder (tests do).

`Router.route` (Routing.swift) picks a project: the first 1-3 spoken words match a name or alias (compared without spaces or punctuation, with a small edit distance
because speech mishears names: none under 4 letters, 1 for 4-5, 2 for 6-7, 3 for 8 or more; the spoken part may be at
most 2 letters shorter than the name, and at distance 3 the consonants must match ("pointtrue" and "pointroo" are both "pntr"); two equally close projects give no
match; the speech model also gets the names as contextual hints), else the points vote by
URL host(:port), host or window title containing the project name, or a `titles` entry (a tie gives nothing), else the
only live session. `Process.run` saves the result as `route.json` ({project, path, how}) in the session folder. When
nothing routes and two or more projects are live, `AppState.stop()` shows a picker; the pick is saved with how `picked`
and its host:port (or window title) is added to that project in `projects.json`. Only dev hosts are learned (localhost,
127.0.0.1, ::1, 0.0.0.0 with their port, and names ending in .test, .local, .localhost, .internal); public hosts such as
claude.ai are never saved, as every project would vote for them. A window title is learned only when nothing on screen had a URL.

`Items.openItems(project:)` hands out items whose path equals or contains/is inside the given path, plus unrouted items.
`wait_for_next` and the Stop hook pass `unrouted: .never`: an item with no route is never handed out to a listener, only to
an explicit `get_open_items`. `wait_for_next` also passes `since` (the time the MCP process started): older recordings are
left alone unless they were routed to this project with how `said`, `screen` or `picked`. If the picker is skipped or
times out the app shows "Not sent - kept in the queue".
MCP `get_open_items` uses the server's cwd (`scope: "all"` turns that off); `wait_for_next` polls every second for one, for up to 50 s per call (max 55 s: the Claude desktop app cancels tool calls at about 60 s).
`PointAndYap --hook-stop` is a Claude Code Stop hook: it reads `cwd` from stdin and, if items are open for it, prints a
block decision (it never takes items). Setup is in the skill file.
