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
- Debug mode (⌥⌘D or Settings): Index Details, a Search Log, and timings in the footer. The Search Log records only this app's own searches, keeps at most 10,000, and stays on this Mac.
- Errors show inline in the panel and in the menu bar.
- Settings for the hotkey, the editor and debug mode.
- Sparkle updater. It stays inactive until the signing keys are configured.
- About FSearch window crediting fsearch by Noah Dunnagan, with the full third-party licenses. It also credits Raycast and Everything as inspiration.
- Third-party notices for fsearch, KeyboardShortcuts and Sparkle ([THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)).
- Privacy manifest declaring no tracking, no data collection and the required-reason APIs the app uses (UserDefaults, file timestamps).
- App category set to Productivity (`LSApplicationCategoryType`).
- Release tooling: `scripts/release.sh` signs, notarizes and staples, verifies the app and DMG signatures, and writes a SHA-256 checksum next to the DMG. A release checklist is in [docs/release-checklist.md](docs/release-checklist.md).
- FSearchKit Swift package with unit and daemon integration tests. A separate UI smoke test (`scripts/ui-smoke.sh`) runs locally, not in CI.
- Benchmarks: `scripts/bench.sh` measures keystroke, client and real-daemon performance and fails when a result regresses against `bench/baseline.json`. See [bench/README.md](bench/README.md).
- A Makefile for common tasks (`make test`, `lint`, `type`, `bench`, `check`) and a `.swift-format` style config.
- CI runs the FSearchKit tests on macOS 14 (Xcode 16.2) and macOS 26 (Xcode 26.6), builds the universal app, lints the scripts and workflows, and reports benchmarks.
- Open-source project files: contributing guide, security policy, code of conduct, architecture overview, issue and pull request templates, CODEOWNERS, and Dependabot for GitHub Actions.
- Documentation ([docs/README.md](docs/README.md)): a first-search tutorial, how-to guides, reference pages (keyboard shortcuts, query syntax, settings, files and locations, troubleshooting, FAQ), architecture decision records, install and uninstall guides, a privacy policy ([Privacy](docs/privacy.md)), support ([Support](.github/SUPPORT.md)) and a roadmap ([Roadmap](docs/roadmap.md)).

### Changed

- Errors from the search daemon read as plain sentences (for example "Can't reach the search daemon"), in the panel and in the debug Search Log, and decode errors name the daemon's own field names.

### Fixed

- While a filter value is still being typed (for example `foo size:`), the panel keeps the current results instead of sending an incomplete query and flashing an error.
- The client checks the id on every reply from the daemon, so a stray or late line can never be shown as the answer to a different search.
- In content search, a filter key with no value yet (for example `ext:`) is treated as a filter, as the daemon does, instead of as search text.
- After a failed search, the debug footer no longer shows the previous search's timing.

### Security

- CI actions are pinned to full commit SHAs, and workflows run with read-only permissions.

[Unreleased]: https://github.com/domfahey/fsearch-app/commits/main
