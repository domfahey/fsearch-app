# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/).
This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Nothing has been released yet. Version 0.1.0 will be the first release.

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
- The app reuses an fsearch daemon that is already running, such as the CLI's.
- Debug mode (⌥⌘D or Settings): Index Details, a Search Log, and timings in the footer. The Search Log records only this app's own searches, keeps at most 10,000, and stays on this Mac.
- Errors show inline in the panel and in the menu bar.
- Settings for the hotkey, the editor and debug mode.
- Sparkle updater. It stays inactive until the signing keys are configured.
- Release script, CI workflow and release checklist.
- FSearchKit Swift package with unit, integration and UI smoke tests.
- Third-party notices for fsearch, KeyboardShortcuts and Sparkle ([THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)).
- Privacy manifest declaring no tracking, no data collection and the required-reason APIs the app uses (UserDefaults, file timestamps).
- App Store category set to Productivity (`LSApplicationCategoryType`).
- About FSearch window (menu bar) crediting fsearch by Noah Dunnagan, with the full third-party licenses (`scripts/gen-credits.sh` builds it from THIRD_PARTY_NOTICES.md).
- Release script verifies the stapled app and DMG and the app signature, and writes a SHA-256 checksum file next to the DMG.
- CI runs the FSearchKit tests on macOS 14 (Xcode 16.2) as well as the current runner.

### Fixed

- The app no longer starts a second helper when another daemon already holds the lock.

### Security

- The app never takes over, stops or replaces a daemon it did not start, so it coexists with a CLI-installed daemon.
- Tests never touch your real index or data folder. They use a temporary `HOME` and `FSEARCH_ROOT`.
- CI actions are pinned to full commit SHAs that are at least two weeks old.
- CI workflows use least-privilege permissions.

[Unreleased]: https://github.com/domfahey/fsearch-app/commits/main
