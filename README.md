# Pointroo

**Pointroo** is a small Mac menu bar app for showing your coding agent what to change. Press Control twice, talk while you
point at things on screen, press Control twice again. Each recording becomes an item in a local queue, with what you said,
the element under the cursor and a cropped screenshot. Claude Code, Codex or Cursor pick it up over MCP, fix it and mark it
done.

Pointroo is a fork of [Point and Yap](https://github.com/mfmaur/pointandyap) by mfmaur (MIT). It is its own app and runs
next to Point and Yap without touching it. On top of the original it adds:

- **Routing**: each recording goes to the right project, by the project name you say, by what is on screen, as a follow-up
  to what an agent just finished, or with a quick picker.
- **Listen mode**: the `wait_for_next` tool lets a session wait for new items, so you paste nothing.
- **A Stop hook** that wakes an idle session when items wait for it.

## Install

Requires macOS 26 or later and a Mac with Apple silicon. Pointroo has no download yet, so you build it:

```bash
bash scripts/build.sh
```

This builds the app and installs it to `/Applications/Pointroo.app` (bundle id `dev.oneroodev.pointroo`). See
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for signing and the dev loop (`bash scripts/dev.sh --watch`).

Open it, allow the three permissions it asks for, and answer one question: it lists the coding agents it found and asks
before connecting them. Connect, or Skip and do it later in Settings.

### Permissions, and why

- **Microphone**: records what you say while you point.
- **Screen Recording**: takes the screenshots at each point and click. The recording pill is never in them.
- **Accessibility**: reads the element under the cursor (role, label, window, app), so an agent can find it in code.

## How it works

1. Press Control twice (or Start recording). A small pill with the time and Stop stays on top.
2. Talk and point: rest the cursor on the thing you mean while you say "this", "here", "that one". Clicks count too.
3. Press Control twice again. A soft sound plays. If only one project has a live agent session, or you named one, the item
   goes there. If it is not clear, a picker asks.
4. The agent calls `get_open_items` (or `wait_for_next`), makes the change and calls `mark_done`. The window shows To fix,
   In progress (by which agent) or Done for each recording.

Esc while recording cancels it and moves it to the Trash.

### Where an item goes

In this order: the project name you say at the start ("Pointroo, ..."), the project your cursor was on (a page on the
project's dev host, or a window with the project's name), a follow-up, the only live agent session, then the picker.

A follow-up means: an agent finished an item in a project less than 3 minutes before you started recording, and a session
is still running in that project. The new item then goes to the same project, and says which item it follows and what the
agent wrote when it finished.

### Runs on your Mac

Speech is transcribed by Apple's on-device model. Recordings, screenshots, the queue and the MCP server all live on your
Mac. No account, no server, no analytics.

Your coding agent is a different matter: when it reads an item, what you said and the crops go to whatever model it uses,
like anything else you show it.

Data lives in:

- `~/Pointroo/sessions`: the recordings and the queue.
- `~/Library/Application Support/Pointroo`: projects, live sessions and config backups.

## MCP tools

`/Applications/Pointroo.app/Contents/MacOS/Pointroo --mcp` is a local MCP server over stdio, named `pointroo`. After you say
Connect, it is added to Claude Code (user scope), Codex (`~/.codex/config.toml`) and Cursor (`~/.cursor/mcp.json`), and the
`pointroo` skill is linked into `~/.claude/skills` and `~/.agents/skills`. Each config is backed up first to
`~/Library/Application Support/Pointroo/backups/`. Pointroo only touches entries named `pointroo`; Point and Yap's entries are
left alone.

| Tool | What it does |
| --- | --- |
| `get_open_items` | The open items for your project, oldest first, with what was said, the elements and the crops. Marks them in progress by the calling agent. |
| `wait_for_next` | Waits up to 50 s for a new item for your project. Call it again in a loop. |
| `start_items` | Marks specific open items in progress by you. |
| `list_items` | Every item with its state: open, in progress (by whom, since when) or done (with the note). |
| `mark_done` | Marks items done with a one-line note. Done items are never handed out again. |
| `release_items` | Gives items back to the queue, with a note why. |
| `list_sessions`, `get_session`, `get_frame` | The recordings themselves: the aligned timeline, crops and full screenshots. |

An item in progress that no one finishes goes back to the queue after two hours. One file lock keeps two agents from taking
the same item.

### Shell fallback

For an agent without MCP:

```bash
/Applications/Pointroo.app/Contents/MacOS/Pointroo --items
```

```bash
POINTANDYAP_AGENT=my-agent /Applications/Pointroo.app/Contents/MacOS/Pointroo --done <id> --note "what changed"
```

## FAQ

**Does anything leave my Mac?** Pointroo sends nothing anywhere. Your coding agent sends what it reads (your words and the
crops) to its model, as with anything you give it.

**Which agents work?** Claude Code, Codex and Cursor are connected for you. Any MCP client that runs a local stdio server
works with the command above, and any agent with a shell can use `--items` and `--done`.

**I skipped connecting. How do I connect later?** Settings, Coding agents, Connect now.

**How do I remove it?** Quit it and delete it from Applications. To remove the agent entries: `claude mcp remove pointroo
--scope user`, the `[mcp_servers.pointroo]` table in `~/.codex/config.toml`, `pointroo` in `~/.cursor/mcp.json`, and the
`pointroo` links in `~/.claude/skills` and `~/.agents/skills`. Recordings are in `~/Pointroo`.

**Does it work on older Macs or Intel?** Not yet. Only speech-to-text needs macOS 26 (SpeechAnalyzer, Apple's on-device
model with word timings, which lines up each word with where the cursor was).

**Can I build it myself?** Yes: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md). `swift test` runs the tests over a synthetic
recording.

## Contributing

Issues and pull requests are welcome: [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues privately as described in
[SECURITY.md](SECURITY.md). This project follows a [code of conduct](CODE_OF_CONDUCT.md).

## License

[MIT](LICENSE). Provided as is, without warranty of any kind. Pointroo is a fork of Point and Yap by mfmaur (MIT).
