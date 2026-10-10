# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).
This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Nothing has been released yet. Version 0.1.0 will be the first release. "Fixed" lists only changes made after the first public push of `main` (2c2d8f9), since people could have built that.

## [Unreleased]

### Added

- Launcher panel, opened with ⌥Space by default. It has a Raycast-style layout: file icons, the name with the match highlighted, and the folder in grey.
- "Use '<query>' with…" rows with two chips: Search inside files and Find definitions.
- A `?` query-syntax cheat sheet. Type `?` alone to see it.
- Recent files when the query is empty.
- The panel resumes where you left off if you reopen it within 60 seconds.
- Keyboard control: ↑ ↓ ⌃N ⌃P to move, ↵ to open, ⌘↵ to reveal, ⌘Y for Quick Look, ⌘⇧C to copy the path, ⌘1–9 to open the Nth file, ⌘K for the actions menu.
- File actions: open, open at a line in VS Code, Cursor, Zed, Sublime Text, BBEdit or Xcode, reveal in Finder, Quick Look, copy path, copy file, open with, open folder in Terminal, move to Trash, and drag a result out.
- Four-step onboarding: choose the hotkey (with a warning when another launcher holds it), turn on the background helper login item, grant Full Disk Access (you can skip it), and watch the first index progress.
- A universal (arm64 and x86_64) fsearch daemon bundled in the app and registered with SMAppService.
- Coexistence with the fsearch CLI: the app reuses a daemon that is already running and never takes over, stops or replaces a daemon it didn't start.
- App commands in the search panel: typing "settings", "preferences" or "prefs" shows an FSearch Settings row below the files, just above the "Use … with" rows, so ↵ still opens the top file; select the row and press ↵ to open Settings. With no matching files the row is first.
- Settings: "Open FSearch at login", with the real login-item status, and "Remove Background Helper and Data…" to uninstall from inside the app. It removes FSearch's own helper (also one still awaiting approval) and moves the logs and settings to the Trash. The index goes too only if FSearch's helper ran the daemon and the fsearch CLI's login agent isn't installed, since the two share one data folder.
- After you skip Full Disk Access during setup, a quiet menu-bar reminder offers "Turn On Full Disk Access…" and "Don't Remind Me". It clears itself once access is granted.
- Help menu (FSearch Help, Keyboard Shortcuts, Query Syntax, Changelog, Privacy) and "Report an Issue…", which opens a pre-filled GitHub bug form with versions, chip and daemon state. It never includes paths or queries.
- Unified logging (`os.Logger`, subsystem `com.domfahey.fsearch`). Paths and queries are never logged in the clear. See [Collecting logs](docs/reference/troubleshooting.md#collecting-logs).
- Debug mode (the menu item, whose ⌥⌘D shortcut works while the menu is open, or Settings): Index Details, a Search Log, and timings in the footer. The Search Log records only this app's own searches, keeps at most 10,000, and stays on this Mac.
- Errors show inline in the panel and in the menu bar. Errors from the search daemon read as plain sentences (for example "Can't reach the search daemon"), in the panel and in the debug Search Log, and decode errors name the daemon's own field names.
- Settings for the hotkey, the editor and debug mode.
- Sparkle updater. It stays inactive until the signing keys are configured. Scheduled updates show as a quiet menu-bar reminder ("Update Available…"), Settings has an Updates section (automatic checks, Check Now), feeds must be signed, system profiling is off, and Sparkle's unused XPC services are removed.
- About FSearch window crediting fsearch by Noah Dunnagan, with the full third-party licenses. It also credits Raycast and Everything as inspiration.
- Third-party notices for fsearch, KeyboardShortcuts and Sparkle ([THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)).
- Privacy manifest declaring no tracking, no data collection and the required-reason APIs the app uses (UserDefaults, file timestamps).
- App category set to Productivity (`LSApplicationCategoryType`).
- Documentation ([docs/README.md](docs/README.md)): a first-search tutorial, how-to guides (including updating), reference pages (keyboard shortcuts, query syntax, settings, files and locations, troubleshooting, FAQ, known limitations), architecture decision records, install and uninstall guides, a privacy policy ([Privacy](docs/privacy.md)), support ([Support](.github/SUPPORT.md)) and a roadmap ([Roadmap](docs/roadmap.md)).
- Only one copy of FSearch runs at a time. Run from the DMG or a translocated download, FSearch offers to move itself to Applications and quits without registering its helper.
- Third-party notices and the About window credit the Rust crates linked into the daemon, with licence texts.
- Development:
  - Release tooling: `scripts/release.sh <version>` sets an increasing build number from git, signs, notarizes and staples, verifies the app and DMG signatures, writes a SHA-256 checksum next to the DMG, and refuses nested binaries with hardened-runtime-weakening entitlements. A release runbook is in [docs/release-checklist.md](docs/release-checklist.md).
  - FSearchKit Swift package with unit and daemon integration tests. A separate UI smoke test (`scripts/ui-smoke.sh`) runs locally, not in CI.
  - Benchmarks: `scripts/bench.sh` measures keystroke, client and real-daemon performance and fails when a result regresses against `bench/baseline.json`. See [bench/README.md](bench/README.md).
  - A Makefile for common tasks (`make test`, `apptest`, `coverage-kit`, `lint`, `type`, `bench`, `check`, `ci`, `doctor`, `install`, `clean`) and a `.swift-format` style config.
  - CI runs the FSearchKit tests on macOS 14 (Xcode 16.2) and macOS 26 (Xcode 26.6), builds the universal app, runs the app's unit tests (AppTests), gates coverage (FSearchKit at 90%, the app's unit tests at 80%), treats compiler warnings as errors, blocks on swift-format lint, checks Markdown links, lints the scripts and workflows, and reports benchmarks.
  - The CI release job runs in the protected `release` environment, only for tags on main, after the kit, app and lint jobs, with a 60-minute timeout. It publishes a draft GitHub release with the DMG, checksum and build-provenance attestation (verify with `gh attestation verify`).
  - Pre-commit scans staged blobs and pre-push scans every unpushed commit for GitHub tokens and EdDSA-style keys. Key and certificate file types are git-ignored.
  - Every public FSearchKit API has a doc comment.
  - Documentation: limitations and update pages, an FAQ glossary, the content-search scope, ADRs 0007–0010, test tiers in the contributing guide, and, in the security policy, known limitations (same-user access to the daemon and its index), scope, a 90-day disclosure target, how to verify a download and a key-compromise process.
  - Repository settings: CodeQL, private vulnerability reporting, protected release environment and tags, and an Actions allow list that requires SHA pins.
  - Open-source project files: contributing guide, security policy, code of conduct, architecture overview, issue and pull request templates, CODEOWNERS, and Dependabot for GitHub Actions.

### Changed

- Editors open through LaunchServices with their URL schemes instead of as FSearch's child process. Xcode opens the file without the line.
- ↵ on an app, script, installer or internet location reveals it in Finder instead of launching it. ⌘K → Open still launches.
- The panel shows at most 1000 results.
- `limit:` now works in name searches, because the app no longer sends its own limit over it.
- The debug search log folder is private (0700) and its file 0600, both excluded from backups. The privacy manifest uses reasons DDA9.1 and C617.1 (the app's own files) for file timestamps.

### Fixed

- The panel no longer opens with its search field behind the menu bar on screens shorter than about 1290pt.
- ↵ and the row shortcuts pressed before results arrive wait for them, instead of opening the previous query's result.
- The results list scrolls to the keyboard selection, and holding ↓/↑ (or ⌃N/⌃P) keeps moving it.
- Opening or revealing a file that has moved or been deleted shows an error, keeps the panel up and doesn't add it to Recents. Open With reports launch errors.
- Open Folder in Terminal on a package opens the folder containing it, and folders with a dot in their name show a folder icon.
- ⌘Y, ⌘K and ⌘⇧C work on non-Latin keyboard layouts.
- The app decides it owns the daemon from the process holding the socket (the `socket.lock` pid, inside the app bundle), not just from its login item. After our helper yields to a CLI daemon the app stops claiming it, and a running CLI daemon is never restarted.
- A leftover fsearch CLI login-agent plist with no daemon behind it no longer leaves FSearch without a daemon: after 10 seconds it starts its own helper.
- After the daemon drops, the panel restarts it up to three times per outage (it stopped after one), one restart at a time, and its "Indexing your disk…" auto-refresh now runs. The indexing poll no longer runs while the panel is hidden.
- After an app update, FSearch restarts its own helper once so the new daemon binary runs.
- Turning on Full Disk Access from the menu takes effect: FSearch restarts its helper when you come back.
- Timeouts, and disconnects after the restarts run out, say "The search helper isn't answering" (also in the menu bar) instead of "Starting search…" forever.
- Older CLI daemons whose status lacks newer fields no longer show a false failure warning.
- Settings, Index Details and Search Log open in front, and the update-available reminder comes back after a relaunch.
- The client checks the id on every reply from the daemon, so a stray or late line can never be shown as the answer to a different search.
- In Inside files and Definitions, a filter word with no value (`kind: Deployment`, `limit: 10`, `path: str`) is searched as text instead of causing a daemon error or a match-all filter. A word starting with a double quote is always text. A key with no value yet (for example `ext:`) is still treated as a filter, as the daemon does.
- While a filter value is still being typed (`foo size:`, `type:c`, `kind:fi`, `size:1mb..`), the panel keeps the current results instead of flashing an error and clearing the list. A half-typed filter no longer leaves stale rows up after the query is replaced or the mode changes.
- Searching for an accented name (`café`) finds files whose names Mac apps stored in decomposed form.
- Recents no longer checks every file's existence on each panel redraw.
- After a failed search, the debug footer no longer shows the previous search's timing.
- The menu-bar status no longer crashes when the app's defaults change off the main thread (a3ad0df).
- ⌃N and ⌃P move the selection even when SwiftUI reports them as control characters (4c49488).

### Security

- The app only talks to a daemon socket owned by the same user. Daemon errors are logged as private.
- The test hooks (`-FSEARCH_SOCKET`, XCTest environment variables) work only in Debug builds.
- Release builds no longer inject `get-task-allow`, and the helper is signed with its own identifier.
- Editors no longer inherit FSearch's Full Disk Access (see Changed).
- The Rust toolchain (1.94.0) and XcodeGen (2.46.0, sha256-checked) are pinned. `dtolnay/rust-toolchain` is no longer used in CI.
- The daemon builds with `cargo build --locked` from the exact pinned commit (a protected tag on the fork), before the signing keychain is imported in CI.
- `Package.resolved` is committed, and CI and release builds use only it.
- CI actions are pinned to full commit SHAs. Workflows are read-only by default; the release job gets write for the draft release and attestation.
- The CI release job builds the project, resolves the Swift packages and archives the app before it imports the signing keychain; after that it only signs, notarizes and packages. The build-number check also compares against earlier `v*` tags, so it runs in CI too. The secret-check hooks check every pushed commit in its own scratch folder, block on a file they can't check, match key file names case-insensitively and catch `ghr_` tokens; CI shellchecks them.
- An OpenSSF Scorecard workflow checks the repository's supply-chain security practices.

[Unreleased]: https://github.com/domfahey/fsearch-app/commits/main
