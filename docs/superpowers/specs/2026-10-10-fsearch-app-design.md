# FSearch for Mac: design

Date: 2026-10-10
Status: draft for review

## Goal

A Mac app that makes [fsearch](https://github.com/noahdunnagan/fsearch) usable
by people who would never touch a command line. Someone downloads it, grants
access once, presses a shortcut, and finds any file (by name, or inside it)
faster than with Spotlight, without ever opening a terminal.

## Decisions

| Question | Decision |
|---|---|
| Raycast extension or standalone app? | Standalone, signed Mac app. A Raycast extension may come later on the same daemon. |
| Launcher panel or search window? | Both, on one engine. The **panel ships first** (v1); the window is v2. |
| Where it lives | Its own repo (`domfahey/fsearch-app`), offered upstream once it works. |
| Signing | Apple Developer ID, notarized. |
| UI technology | Native: SwiftUI, with AppKit where needed (floating panel, hotkey, Quick Look, drag and drop). |
| Engine | The existing fsearch daemon, bundled, over its JSON-lines socket API. |
| Platform | macOS 14 (Sonoma) and later, Apple silicon and Intel. |

Rejected: Tauri (a web UI is weakest exactly where a launcher must feel
native: panel focus, translucency, Quick Look, dragging files out) and
Electron (slow start, heavy memory).

## Architecture

### App bundle

```
FSearch.app/Contents/
  MacOS/FSearch                                 the app
  Helpers/fsearch                               pinned upstream daemon, universal, Developer ID signed
  Library/LaunchAgents/<team-id>.fsearch.plist  login item, run via SMAppService as `fsearch serve`
```

`<team-id>` is the Apple Developer team ID the app is signed with.

### Components

Each has one job and is testable on its own.

1. **DaemonClient**: async JSON-lines client for the socket
   (`~/Library/Application Support/FSearch/fsearch.sock`). Requests carry an
   `id`; a response for a superseded query is dropped. Two connections: one for
   name searches, one for content and symbol searches. The daemon answers each
   connection in order, so a slow content search never delays a keystroke's
   name results.
2. **DaemonManager**: registers and unregisters the login item
   (`SMAppService`), checks health (`ping`, `status`), restarts the daemon, and
   compares the running daemon's version with the bundled one.
3. **SearchModel**: observable state for one search box (query, mode,
   results, loading, error). The v2 window reuses it.
4. **LauncherPanel**: floating `NSPanel` plus the global hotkey.
5. **Onboarding**: the first-run flow (below).
6. **Actions**: open, open at line, reveal in Finder, Quick Look, copy path,
   copy file, open with, open folder in Terminal, move to Trash.
7. **MenuBar**: status, Settings, Debug (when on), Quit.
8. **Debug**: Index Details and Search Log windows (below).

### Startup and daemon ownership

- If a daemon already answers on the socket (for example a CLI install's), the
  app uses it and does not register a second one.
- Otherwise the app registers its bundled helper with `SMAppService`; macOS
  starts it now and at every login.
- The app and the CLI share one data folder and one index. Full Disk Access
  belongs to whichever daemon runs; the app's Developer-ID-signed helper keeps
  its grant across updates.

### Searching

- **Names:** one request per keystroke, no debounce (name search takes about
  0.2–3 ms on a 7.9M-entry index). Answers to superseded queries are dropped.
- **Content and symbols:** only when chosen (see "Panel" below), with the
  daemon's 250 ms time budget.
- **Icons:** `NSWorkspace` file icons, cached by file type.

## Panel (v1)

Layout A from the brainstorm, after Raycast's file results:

- One large search field; a sectioned list; a translucent rounded panel; an
  action bar at the bottom ("Open ↵", "Reveal in Finder ⌘↵", "Actions ⌘K").
- **Rows:** the real system file icon, the file name (the matched part
  highlighted), then its folder in grey. There's no right-hand column.
- **Sections:** "Files" (name matches, typo-tolerant), then **"Use '<query>'
  with…"**, offering *Search inside files* and *Find definitions*.
- Choosing one puts an "Inside files" (or "Definitions") chip in the field.
  Rows then show the matching line where the folder was, one row per hit.
  Backspace on an empty field, or Esc, drops the chip and returns to names.
- **Empty query:** the last 8 files opened from the panel.
- **Results:** up to 50 name results (the daemon's default limit).

### Showing and hiding

- The hotkey toggles the panel, centred on the active screen.
- Esc clears the query (or drops the chip); a second Esc hides the panel.
  Clicking outside hides it.
- Reopening within 60 seconds resumes the last query and selection; after that
  it opens empty.

### Keys

| Key | Action |
|---|---|
| ↑ ↓, ⌃N ⌃P | Move the selection |
| ↵ | Open in the default app; for content hits, open at the matching line |
| ⌘↵ | Reveal in Finder |
| ⌘Y | Quick Look |
| ⌘⇧C | Copy path |
| ⌘1 – ⌘9 | Open the nth result |
| ⌘K | Actions menu |

**⌘K menu:** Open, Open With ▸, Reveal in Finder, Quick Look, Copy Path, Copy
File, Open Folder in Terminal, Move to Trash. Trash has no direct shortcut.

**Drag and drop:** a row can be dragged into Finder, Mail, Slack and so on.

**Open at line:** a setting picks the editor for content results. Installed
editors that support line numbers (VS Code, Cursor, Zed, Sublime Text, BBEdit,
Xcode) are detected. With none chosen, ↵ opens the file.

**Query syntax:** fsearch filters (`ext:`, `in:`, `type:`, `kind:`, `size:`,
`mtime:` and so on) are passed through to the daemon as typed. A "?" in the
field shows a cheat sheet. Clickable filter chips are v2.

**Apps:** apps are files too. Typing "chrome" finds Google Chrome.app, and ↵
opens it. No separate app launcher is needed.

## Onboarding

One small window, four steps. Each step checks its own result before
continuing.

1. **Welcome and shortcut:** choose the global hotkey (default ⌥ Space). If
   another app owns it (Raycast uses ⌥ Space, for example), say so and offer to
   change it.
2. **Background helper:** register the login item. If macOS requires approval,
   a button opens Login Items settings
   (`SMAppService.openSystemSettingsLoginItems()`), and the step waits until
   the item is enabled.
3. **Full Disk Access:** explain which folders macOS hides without it
   (Desktop, Documents, Downloads, Mail, Messages, iCloud Drive), and that the
   index never leaves the Mac. Open the Privacy & Security → Full Disk Access
   pane. Watch for the grant by restarting the helper and reading
   `status.full_disk_access` until it's true. **Skip for now** still gives
   working search without the protected folders, plus a menu-bar reminder.
4. **First index:** show progress from `status` ("4.8 million files so
   far…"), then end with "press ⌥ Space and type part of any file name".

## Debug mode

Turned on in Settings, or by ⌥-clicking the menu-bar icon. While it's on, a
small "debug" dot shows in the panel's search field.

### Index Details window

Refreshed live:

- **From `status`:** entries, folders, overlay and removed counts, last
  FSEvents id, index size, content docs, segments and size, files waiting to
  be content-indexed, Full Disk Access, owner or follower.
- **Around it:** daemon version and pid, the data folder (with Reveal), the
  folders listed in `skipped`, and the tail of `daemon.log`.
- **Buttons:** Save Now (compact), Restart Daemon, Copy All.

### Search log

The log records **every request the daemon answers**, from any client (the
app, the CLI, `fsearch stdio` editors and MCP tools, other apps).

- It needs an upstream daemon change (see "Upstream changes"): a socket op
  toggles the log, and while on, the daemon appends each request to
  `searches.jsonl` in its data folder. Each entry records the time, the client
  (from the connecting process's pid via the socket, resolved to a name), the
  op, the query, the result count, the daemon's own timing, and for content
  searches the candidates read and whether the time budget ran out.
- The app shows the log as a live, filterable table, client included, with
  export to JSON lines. For its own searches it adds its round-trip time.
- In the panel, debug mode adds a footer line ("1.4 ms · 50 results") and each
  row's score.

### Privacy

- Logging is off by default and only on while debug mode is on. `status`
  reports it.
- The log stays on this Mac, in the daemon's data folder.
- It's capped at the last 10,000 requests.
- Clear Log empties it. Turning debug mode off turns logging off.

### Order of work

Debug mode ships first with Index Details and the app's own searches. It
switches to the daemon's log once that change is merged upstream, so v1 isn't
blocked on the maintainer.

## Upstream changes (PRs to fsearch)

1. **Version in `status`,** so the app can detect a mismatched daemon.
2. **Agent ownership:** a daemon can declare itself agent-owned (for example
   with an environment variable set in its plist), so the app's agent takes
   over from a stray daemon instead of being respawned forever. Today only the
   CLI's `mt.nd.fsearch` label is recognised.
3. **Query log:** the `log` op, `searches.jsonl`, and the client from the peer
   pid, as described above.

These come after the current #12 → #13 → #14 stack lands.

## Errors

Errors are shown where the user is looking; routine problems never get a modal.

- **Bad query** (for example an unclosed regex): a one-line message under the
  field; results resume once it's fixed.
- **Daemon unreachable:** "Starting search…" while it restarts. If that fails,
  a menu-bar warning with "Fix…", which opens Index Details.
- **Still indexing:** "Indexing your disk… results will appear shortly", and
  retry.
- **Full Disk Access revoked:** detected from `status`; a gentle menu-bar
  reminder.
- **A different fsearch running** (an older CLI daemon): a banner with both
  versions and how to switch. The app doesn't stop a daemon it didn't start.
- **Icons and Quick Look:** quiet fallbacks (a generic icon, no preview).

## Testing

- **Unit tests (Swift Testing):**
  - DaemonClient against a scripted fake socket server: id matching, dropped
    stale answers, reconnecting;
  - SearchModel state transitions;
  - key handling written as a pure function of state and key.
- **Integration tests** against the real bundled `fsearch`, with a temp `HOME`
  and `FSEARCH_ROOT` (the isolation the Rust CLI tests use). Never the user's
  real index.
- **UI smoke tests (XCUITest):** open the panel, type, see results, run an
  action.
- **Manual release checklist:** signing, notarization, Full Disk Access, the
  login item, upgrading over the previous version.
- **CI:** GitHub Actions on macOS. Build the universal app and run the tests;
  sign and notarize only on tagged releases.

## Distribution

A signed, notarized DMG, with Sparkle auto-updates (signed appcast). A
Homebrew cask later.

## First step before building

An experiment to settle **how macOS attributes Full Disk Access to an
`SMAppService` helper**: does granting access to FSearch.app cover the bundled
helper, or must the helper be added itself? Onboarding step 3's wording
depends on the answer; its flow (watch `status.full_disk_access`) holds either
way.

## Implementation notes (v1)

Where the shipped v1 differs from this spec:

- The bundled LaunchAgent plist is `com.domfahey.fsearch.daemon.plist`, not
  `<team-id>.fsearch.plist`.
- The engine is built from the `domfahey/fsearch` fork at a pinned commit
  (`scripts/build-daemon.sh`) until the upstream PRs merge; then it moves to an
  upstream tag.
- The ⌥-click debug toggle is replaced by a Debug Mode menu item (⌥⌘D) and a
  toggle in Settings.
- Index Details doesn't show the daemon's pid yet; that waits on upstream
  `status` reporting it.
- The Full Disk Access attribution experiment ("First step before building",
  Task 0) is still open; it is tracked in `docs/release-checklist.md`.

## Out of scope for v1

- The search window (v2), with clickable filter chips, sorting and previews.
- A Raycast extension.
- Commands, AI features, or anything beyond finding and acting on files.
