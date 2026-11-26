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
- File actions: open, open at a line in VS Code, Cursor, Zed, Sublime Text or BBEdit (Xcode opens the file without the line), reveal in Finder, Quick Look, copy path, copy file, open with, open folder in Terminal, move to Trash, and drag a result out.
- Four-step onboarding: choose the hotkey (with a warning when another launcher holds it), turn on the background helper login item, grant Full Disk Access (you can skip it), and watch the first index progress.
- A universal (arm64 and x86_64) fsearch daemon bundled in the app and registered with SMAppService.
- Coexistence with the fsearch CLI: the app reuses a daemon that is already running and never takes over, stops or replaces a daemon it didn't start.
- App commands in the search panel: typing "settings", "preferences" or "prefs" shows an FSearch Settings row below the files, just above the "Use … with" rows, so ↵ still opens the top file; select the row and press ↵ to open Settings. With no matching files the row is first. VoiceOver can activate the row, as it can the "Use … with" rows.
- Settings: the hotkey, the editor, debug mode, "Open FSearch at login" (with the real login-item status), an Updates section (automatic checks, Check Now) and "Remove Background Helper and Data…" to uninstall from inside the app. The uninstaller removes FSearch's own helper (also one still awaiting approval), waits for the unregistered helper to stop, resets the app's settings (including Sparkle's defaults) and moves its logs to the Trash, then refreshes the login-item status in Settings. The helper and index stay removed until setup runs again: automatic recovery is suspended across launches and waits for pending restarts, and coming back to the app does not reinstall it. The index goes too only if FSearch's own helper is confirmed to hold it and the fsearch CLI's login agent isn't installed, since the two share one data folder; otherwise it is kept and the uninstaller says why: the helper is off, another fsearch daemon holds it, or it couldn't confirm.
- After you skip Full Disk Access during setup, a quiet menu-bar reminder offers "Turn On Full Disk Access…" and "Don't Remind Me". It clears itself once access is granted. Turning access on from the menu takes effect: FSearch restarts its helper as soon as the grant shows, or at the latest when you come back.
- An FSearch menu in the panel, like Raycast's. Open it with ⌘/ or the gear at the left of the footer. It shows the version and has Send Feedback, Manual, Keyboard Shortcuts, Changelog, About FSearch, Settings…, GitHub, Discussions and Quit FSearch, with a "Search for actions…" field to filter them. Opening it resigns search-field focus and defers focusing its filter field; closing it restores search-field focus after, and only while the panel is still visible.
- Help menu (FSearch Help, Keyboard Shortcuts, Query Syntax, Changelog, Privacy, GitHub, Discussions) and "Report an Issue…", which opens a pre-filled GitHub bug form with versions, chip and daemon state. It never includes paths or queries.
- Unified logging (`os.Logger`, subsystem `com.domfahey.fsearch`). Paths and queries are never logged in the clear. See [Collecting logs](docs/reference/troubleshooting.md#collecting-logs).
- Debug mode (the menu item, whose ⌥⌘D shortcut works while the menu is open, or Settings): Index Details, a Search Log, and timings in the footer. The Search Log records only this app's own searches, keeps at most 10,000, and stays on this Mac.
- Errors show inline in the panel and in the menu bar. Errors from the search daemon read as plain sentences (for example "Can't reach the search daemon"), in the panel and in the debug Search Log, and decode errors name the daemon's own field names.
- Sparkle updater. It stays inactive until the signing keys are configured. Scheduled updates show as a quiet menu-bar reminder ("Update Available…"), the reminder comes back after a relaunch, Settings has an Updates section, feeds must be signed, system profiling is off, and Sparkle's unused XPC services are removed. After an app update, FSearch restarts its own helper once so the new daemon binary runs. A version marker records the helper that is running, and a failed replacement keeps the previous marker: if the old helper is still answering after it was unregistered, the login item is put back without recording the update, so a later launch retries. The old helper still counts as FSearch's own while it runs from the Trash or Sparkle's temporary folder.
- About FSearch window crediting fsearch by Noah Dunnagan, with the full third-party licenses. It also credits Raycast and Everything as inspiration.
- Third-party notices for fsearch, KeyboardShortcuts, Sparkle and the Rust crates linked into the daemon, with licence texts ([THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)). The About window credits the same crates.
- Privacy manifest declaring no tracking, no data collection and the required-reason APIs the app uses (UserDefaults, file timestamps).
- App category set to Productivity (`LSApplicationCategoryType`).
- Documentation ([docs/README.md](docs/README.md)): a first-search tutorial, how-to guides (including updating), reference pages (keyboard shortcuts, query syntax, settings, files and locations, troubleshooting, FAQ, known limitations), architecture decision records, install and uninstall guides, a privacy policy ([Privacy](docs/privacy.md)), support ([Support](.github/SUPPORT.md)) and a roadmap ([Roadmap](docs/roadmap.md)).
- Only one copy of FSearch runs at a time. Run from the DMG or a translocated download, FSearch offers to move itself to Applications and quits without registering its helper. It opens the moved copy only after the old one has quit.
- Accessibility support: panel and FSearch menu adapt to Reduce Motion, Reduce Transparency (opaque surfaces), and Increase Contrast (stronger selection/chip/keycap contrast, borders, and underlined match highlights); debug windows, Settings, and Onboarding respect Reduce Motion; Onboarding Continue/Done and Settings Done support the default Return shortcut; VoiceOver gets section/step headings, clean warning labels, search-mode/debug indicators, a labeled Search Log filter, and warning/update-aware menu-bar labels.
- URL scheme (`fsearch://search?q=…&mode=names|content|symbols`) to open the launcher panel pre-filled with a query and search mode from scripts, Shortcuts or other apps. See [URL scheme](docs/reference/url-scheme.md).
- App Intents: a **Search Files** action for Apple Shortcuts and Spotlight (file names, inside files or symbol definitions, with a configurable result limit) that queries the daemon in the background and returns matching files. See [Shortcuts (App Intents)](docs/reference/shortcuts.md).
- Localization readiness: English String Catalogs for both the app (`App/Resources/Localizable.xcstrings`) and `FSearchKit` (`Packages/FSearchKit/Sources/FSearchKit/Resources/Localizable.xcstrings`), with `en` development region, `LocalizedStringKey`/`String(localized:)` coverage across SwiftUI views, AppKit menus/alerts/windows and package copy, `Text(verbatim:)` for non-translatable technical tokens, and `make strings` (`scripts/sync-strings.sh`) to keep both catalogs in sync.
- Development:
  - Release tooling: `scripts/release.sh <version>` sets an increasing build number from git, signs, notarizes and staples, verifies the app and DMG signatures, writes a SHA-256 checksum next to the DMG, and refuses nested binaries with hardened-runtime-weakening entitlements. `scripts/appcast.sh <version> <archives-dir>` extracts the version's release notes from `CHANGELOG.md` and runs Sparkle's `generate_appcast` with embedded release notes and binary deltas. A release runbook is in [docs/release-checklist.md](docs/release-checklist.md).
  - FSearchKit Swift package with unit and daemon integration tests. A separate UI smoke test (`scripts/ui-smoke.sh`) runs locally, not in CI.
  - Benchmarks: `scripts/bench.sh` measures keystroke, client and real-daemon performance and fails when a result regresses against `bench/baseline.json`. See [bench/README.md](bench/README.md).
  - A Makefile for common tasks (`make test`, `apptest`, `coverage-kit`, `lint`, `type`, `bench`, `check`, `ci`, `doctor`, `install`, `clean`) and a `.swift-format` style config.
  - CI runs the FSearchKit tests on macOS 26 (Xcode 26.6), builds the universal app, runs the app's unit tests (AppTests), gates coverage (FSearchKit at 95%, the app's unit tests at 95%), treats compiler warnings as errors, blocks on swift-format lint, checks Markdown links, lints the scripts and workflows, and checks benchmarks against the `ci-macos-26` baseline.
  - The CI release job runs in the protected `release` environment, only for tags on main, after the kit, app and lint jobs, with a 60-minute timeout. It publishes a draft GitHub release with the DMG, checksum and build-provenance attestation (verify with `gh attestation verify`).
  - Pre-commit scans staged blobs and pre-push scans every unpushed commit for GitHub tokens and EdDSA-style keys. Key and certificate file types are git-ignored.
  - Every public FSearchKit API has a doc comment.
  - Documentation: limitations and update pages, an FAQ glossary, the content-search scope, ADRs 0007–0012, test tiers in the contributing guide, deeper daemon-verified query syntax docs (ranking, typo tolerance, word combining, `limit:`), and, in the security policy, known limitations (same-user access to the daemon and its index), scope, a 90-day disclosure target, how to verify a download and a key-compromise process.
  - Repository settings: CodeQL for Swift and the workflows, private vulnerability reporting, a protected `main` (required checks on up-to-date branches, linear history, squash merges), a protected release environment and tags, and an Actions allow list that requires SHA pins.
  - Open-source project files: contributing guide, security policy, code of conduct, architecture overview, issue and pull request templates, CODEOWNERS, and Dependabot for GitHub Actions.

### Changed

- The minimum macOS is now 15 (Sequoia). CI no longer runs on the retiring macOS 14 image.
- Editors open through LaunchServices with their URL schemes instead of as FSearch's child process. Xcode opens the file without the line.
- ↵ on an app, script, installer or internet location reveals it in Finder instead of launching it. ⌘K → Open still launches. The same goes for more types that run or install something when opened: `.mobileconfig`, `.prefpane`, `.saver`, `.qlgenerator`, `.osax`, `.action`, `.shortcut`, `.jar`, `.jnlp`, `.scptd` and `.dmg`.
- Warnings and errors now say "background helper" instead of "search helper" ("The background helper isn't answering", and so on).
- The Search Log drops entries older than 7 days, as well as keeping only the newest 10,000. Its temporary file for a rewrite is created 0600.
- File names and folder paths in the panel are shown with invisible and bidirectional control characters replaced by a visible marker (U+FFFD), so a name like `invoice‮fdp.exe` can't pass for a PDF. Only the display changes; actions use the real path (`DisplaySafe`).
- The Shortcuts **Search Files** action refuses **Inside Files**, **Definitions** and content filters unless you turn on **Allow Shortcuts to search inside files** in Settings (off by default). File name searches always work. See [Shortcuts](docs/reference/shortcuts.md#searching-inside-files).
- The panel shows at most 1000 results.
- `limit:` now works in name searches, because the app no longer sends its own limit over it.
- The debug search log folder is private (0700) and its file 0600, both excluded from backups. The privacy manifest gives one reason for file timestamps, C617.1: the app reads them only for its own files and never shows them.
- CI's coverage gates are now 95% for both FSearchKit and the app's unit tests (up from 90% each).
- CI's `bench` job now compares against a `ci-macos-26` baseline in `bench/baseline.json` (seeded from five hosted `macos-26` runs with hosted-runner tolerances), failing on reproduced regressions while warning on inconclusive busy-runner runs (exit 75).

### Fixed

- Socket replies must finish within the request timeout, even when partial data keeps arriving.
- A file refused by its default app shows an error and keeps the panel open without adding a recent; a failed editor fallback also reports the error.
- Opening or reopening the panel (including with the global shortcut) defers search-field focus until after activation and presentation so typing works immediately without clicking first.
- Copy File, Open Folder in Terminal, and Quick Look check whether a file still exists before acting and report a missing-file error instead of failing silently; Quick Look still closes when a preview is already open.
- The footer shows `Open at line` when the chosen editor handles open-at-line links, Settings keeps an uninstalled editor selection visible in its picker, and onboarding automatically detects a Full Disk Access grant while open.
- Disconnect-driven helper restarts and recovery refreshes coalesce across rapid failures so they don't burn extra restart budget tokens, and `DaemonManager.start()` waits for any in-flight restart.
- Socket transport caps incoming reply lines at 64 MiB, retries partial writes and `EINTR`, rejects embedded NUL bytes in socket paths, and handles invalid timeouts without trapping; query parsing, search debouncing, recents caching, and search-log rotation/truncation edge cases are hardened.
- Build, coverage, link-check, benchmark, credit-generation, release, and hook scripts plus docs and benchmarks are fixed and kept in sync with macOS 15+.
- The ⌘K actions menu opens under the selected row, or under the search field when that row is out of view, instead of at a fixed spot.
- ⌘Y, ⌘K, ⌘⇧C, ⌘1–9, ⌘↵ and ↵ no longer fire with ⌃ or ⌥ held too, so ⌘⌃Y no longer opens Quick Look.
- In Quick Look, ↑ and ↓ move the panel's selection and the preview follows it.
- Backspace in an empty search field drops the Inside files or Definitions chip again. It only matched the key some synthesized events send, not a real keyboard's Backspace.
- The panel no longer opens with its search field behind the menu bar on screens shorter than about 1290pt.
- ↵ and the row shortcuts pressed before results arrive wait for them, instead of opening the previous query's result. New results put the selection back on the top row first, so a waiting key never opens a row picked from the old results. A waiting key is dropped if the panel is hidden, the search fails or the index is still building, and it acts on the rows shown while a filter is still being typed (`foo ext:`) instead of being swallowed.
- The results list scrolls to the keyboard selection, and holding ↓/↑ (or ⌃N/⌃P) keeps moving it.
- Opening or revealing a file that has moved or been deleted shows an error, keeps the panel up and doesn't add it to Recents. Open With reports launch errors.
- Open Folder in Terminal on a package opens the folder containing it, and folders with a dot in their name show a folder icon, in Recents too.
- ⌘Y, ⌘K and ⌘⇧C work on non-Latin keyboard layouts.
- The app decides it owns the daemon from the process holding the socket (the `socket.lock` pid, inside the app bundle), not just from its login item. After our helper yields to a CLI daemon the app stops claiming it, and a running CLI daemon is never restarted.
- A leftover fsearch CLI login-agent plist with no daemon behind it no longer leaves FSearch without a daemon: after 10 seconds it starts its own helper.
- After the daemon drops, the panel restarts it up to three times per outage (it stopped after one), one restart at a time, and its "Indexing your disk…" auto-refresh now runs. The indexing poll no longer runs while the panel is hidden.
- Timeouts, and disconnects after the restarts run out, say "The background helper isn't answering" (also in the menu bar) instead of "Starting search…" forever. The message clears as soon as a search works again.
- Older CLI daemons whose status lacks newer fields no longer show a false failure warning.
- Settings, Index Details and Search Log open in front.
- The client checks the id on every reply from the daemon, so a stray or late line can never be shown as the answer to a different search.
- In Inside files and Definitions, a filter word with no value (`kind: Deployment`, `limit: 10`, `path: str`) is searched as text instead of causing a daemon error or a match-all filter. A word starting with a double quote is always text, so `"ext:` no longer holds back the search. A key with no value yet (for example `ext:`) is still treated as a filter, as the daemon does.
- While a filter value is still being typed (`foo size:`, `type:c`, `kind:fi`, `size:1mb..`), the panel keeps the current results instead of flashing an error and clearing the list. A half-typed filter no longer leaves stale rows up after the query is replaced, a tail is pasted onto it, or the mode changes.
- Searching for an accented name (`café`) finds files whose names Mac apps stored in decomposed form.
- Less work on the main thread: Recents no longer checks every file's existence on each panel redraw, the footer works out the return action once per selected row, and in debug mode the Search Log file is secured once instead of on every search.
- After a failed search, the debug footer no longer shows the previous search's timing.
- The menu-bar status no longer crashes when the app's defaults change off the main thread (a3ad0df).
- ⌃N and ⌃P move the selection even when SwiftUI reports them as control characters (4c49488).
- When the chosen editor doesn't handle open-at-line links, a content hit opens in it as a plain file, without the line, instead of not opening.
- VoiceOver can activate the panel's "Use … with" rows. Before, only a click ran them.

### Security

- The app only talks to a daemon socket owned by the same user. Daemon errors are logged as private.
- The test hooks (`-FSEARCH_SOCKET`, XCTest environment variables) work only in Debug builds.
- Release builds no longer inject `get-task-allow`, and the helper is signed with its own identifier.
- Editors no longer inherit FSearch's Full Disk Access (see Changed).
- After another app opens the panel (an `fsearch://` URL or a reopen), ↵, ⌘↵ and ⌘1–9 are ignored for 0.5 s, so a stray keypress can't open the selected file. The hotkey and menu don't start the wait.
- Before an editor is sent a file path, its code signature is checked (Apple-anchored, with the editor's own identifier and its developer's pinned team; Xcode must be Apple's own). A fake app that claims an editor's bundle id is not used: the file opens in the default app and the footer says so.
- Index Details has a **Data folder safety** section: a read-only check for a symlinked or foreign-owned data folder or socket files, or a data folder others can write to. Remove Background Helper and Data… leaves a symlinked or foreign-owned data folder alone.
- The app names the daemon on the socket by its code signature (the connection's audit token), not only by the pid in `socket.lock`, which any process running as you could write. Index Details shows the result in a **Daemon** row.
- The Shortcuts **Search Files** action can no longer search file contents until you allow it (see Changed).
- CI scans the daemon's crates and the Swift packages for known advisories (`.github/workflows/deps.yml`: cargo-deny, policy in `.github/cargo-deny.toml`, and osv-scanner), on pull requests, on `main` and weekly.
- Each release publishes a CycloneDX SBOM of the daemon's crates with its own attestation, next to the DMG.
- Release script hardening: `scripts/appcast.sh` verifies the DMG's checksum and build-provenance attestation before it signs the appcast (`--skip-attestation` is for local dry runs only) and no longer finds `generate_appcast` or `sign_update` on `PATH`; `scripts/release.sh` checks that the signed helper satisfies the app's runtime signature requirement and that `DEVELOPER_ID` is the required team, and calls system tools by absolute path; the CI signing steps run in a fixed shell with a reset `PATH`. `scripts/test-appcast-verify.sh` tests the appcast checks.
- The daemon build is more reproducible: builder paths are remapped out of the binary and timestamps are pinned to the commit.
- The Rust toolchain (1.94.0), XcodeGen (2.46.0), actionlint (1.7.12) and shellcheck (0.11.0) are pinned; the downloaded tools are sha256-checked. `dtolnay/rust-toolchain` is no longer used in CI.
- The daemon builds with `cargo build --locked` from the exact pinned commit (a protected tag on the fork), before the signing keychain is imported in CI.
- `Package.resolved` is committed, and CI and release builds use only it.
- CI actions are pinned to full commit SHAs. Workflows are read-only by default; the release job gets write for the draft release and attestation.
- The CI release job builds the project, resolves the Swift packages and archives the app before it imports the signing keychain; after that it only signs, notarizes and packages. The build-number check also compares against earlier `v[0-9]*` tags, so it runs in CI too. The secret-check hooks check every pushed commit in its own scratch folder, block on a file they can't check, match key file names case-insensitively and catch `ghr_` tokens; CI shellchecks them.
- An OpenSSF Scorecard workflow checks the repository's supply-chain security practices.
- FSearch treats a running daemon as its own helper only when it is the helper inside FSearch's own app, or a helper left running from an older copy of the app (in a `Contents/Helpers` folder, or deleted) that is signed with FSearch's Developer ID as the helper. Anything else, including a signed copy of the helper on the `PATH`, is left alone. Only a development build, which has no Developer ID signature, also accepts an unsigned FSearch.app helper.

[Unreleased]: https://github.com/domfahey/fsearch-app/commits/main
