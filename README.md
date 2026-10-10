# FSearch for Mac

[![CI](https://github.com/domfahey/fsearch-app/actions/workflows/ci.yml/badge.svg)](https://github.com/domfahey/fsearch-app/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-lightgrey.svg)

A fast, keyboard-driven file search launcher for the Mac menu bar.

FSearch for Mac is a native SwiftUI and AppKit app. Press a hotkey, type, and find any file by name or by what is inside it. It targets macOS 14 and later.

FSearch for Mac is a graphical front end for [fsearch](https://github.com/noahdunnagan/fsearch), the fast file-search daemon by Noah Dunnagan. All indexing and searching is done by fsearch. This app bundles a pinned build of fsearch and talks to it over its socket API. This is an independent project and is not affiliated with fsearch or its author.

## Features

- Launcher panel on ⌥Space (configurable), with file icons, match highlighting and the folder in grey.
- Search by name, search inside files, or find definitions.
- Query filters such as `ext:`, `in:`, `type:`, `size:` and `mtime:`. Type `?` for the cheat sheet.
- Recent files when the query is empty. Reopen the panel within 60 seconds to resume.
- Actions: open, open at a line in VS Code, Cursor, Zed, Sublime Text, BBEdit or Xcode, reveal, Quick Look, copy path or file, open with, open folder in Terminal, move to Trash, and drag a result out.
- Four-step onboarding, with a warning if another launcher holds your hotkey.
- Debug mode with Index Details, a local Search Log and timings.
- Sparkle updates (inactive until signing keys are configured).

## Requirements

- macOS 14 (Sonoma) or later, Apple silicon or Intel.
- Full Disk Access is optional but lets FSearch index the whole disk.

## Install

Releases are not published yet. When they are, download the DMG from the [Releases](https://github.com/domfahey/fsearch-app/releases) page and drag FSearch to Applications.

Until then, build from source. See [Development](#development).

## Usage

Press ⌥Space to open the panel and start typing. Below the results, choose **Search inside files** or **Find definitions** to change what the query searches. Type `?` alone to see the query syntax.

| Key | Action |
|---|---|
| ↑ ↓ or ⌃N ⌃P | Move the selection |
| ↵ | Open |
| ⌘↵ | Reveal in Finder |
| ⌘Y | Quick Look |
| ⌘⇧C | Copy path |
| ⌘1–9 | Open the Nth file |
| ⌘K | Actions menu |
| ⌥⌘D | Toggle debug mode |

## How it works

The app bundles a universal (arm64 and x86_64) fsearch daemon and registers it as a background login item with SMAppService. The app talks to the daemon over a local Unix socket in `~/Library/Application Support/FSearch`.

If a daemon is already answering, such as one installed by the fsearch CLI (`fsearch install --login`), the app uses it. It never stops or replaces a daemon it did not start.

## Development

### Prerequisites

- Xcode 16 or later (Swift 6). CI uses Xcode 26.6; on this machine it is selected with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (Xcode 26.6).
- Rust via [rustup](https://rustup.rs), with both macOS targets: `rustup target add aarch64-apple-darwin x86_64-apple-darwin`.
- XcodeGen: `brew install xcodegen`.

### Build and test

Run these from the repository root, in order:

1. `scripts/build-daemon.sh` builds the pinned fsearch daemon as a universal binary into `Vendor/fsearch`. Everything below needs it.
2. `xcodegen generate` generates `FSearch.xcodeproj`.
3. Build the universal app (the same command CI runs):

   ```sh
   xcodebuild -project FSearch.xcodeproj -scheme FSearch -configuration Debug \
     -derivedDataPath build -destination 'generic/platform=macOS' \
     CODE_SIGN_IDENTITY=- build
   ```

4. `cd Packages/FSearchKit && swift test` runs the core tests. They run against the real daemon, so `Vendor/fsearch` must exist first.
5. `scripts/ui-smoke.sh` runs the panel UI smoke test (AppUITests) against a throwaway daemon. It needs a logged-in GUI session and accessibility permission for the test runner, so it doesn't run in CI or over SSH.

Tests never touch your real index: the core tests and the UI smoke test start their own daemon with a temporary `HOME` and `FSEARCH_ROOT`, and the app's test mode never registers the login daemon.

Releases: `scripts/release.sh` and [docs/release-checklist.md](docs/release-checklist.md).

The design spec is in `docs/superpowers/specs/` and the implementation plan is in `docs/superpowers/plans/`.

### Project layout

| Path | What it holds |
|---|---|
| `App/` | The app: panel, actions, daemon manager, onboarding, settings, debug views, updater |
| `AppUITests/` | UI smoke test for the panel |
| `Packages/FSearchKit/` | Core logic and its unit and integration tests |
| `scripts/` | Daemon build, release and UI smoke scripts |
| `docs/` | Release checklist, design spec and plan |

## Privacy

Your index and logs stay on your Mac. The app has no telemetry and makes no network requests of its own. The only network code is the Sparkle updater, which checks for updates once it is configured. The debug Search Log records only this app's searches and stays local.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Please follow the [Code of Conduct](CODE_OF_CONDUCT.md). To report a vulnerability, see [SECURITY.md](SECURITY.md). Changes are listed in the [Changelog](CHANGELOG.md).

## License

MIT. See [LICENSE](LICENSE). Bundled components are covered in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Acknowledgements

- [fsearch](https://github.com/noahdunnagan/fsearch) by Noah Dunnagan. It does all the indexing and searching. FSearch for Mac is an independent front end and is not affiliated with it.
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus, for the global hotkey.
- [Sparkle](https://sparkle-project.org) for updates.

Full license texts are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
