# FSearch for Mac

[![CI](https://github.com/domfahey/fsearch-app/actions/workflows/ci.yml/badge.svg)](https://github.com/domfahey/fsearch-app/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-lightgrey.svg)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/domfahey/fsearch-app/badge)](https://scorecard.dev/viewer/?uri=github.com/domfahey/fsearch-app)

A fast, keyboard-driven file search launcher for the Mac menu bar, built on [fsearch](https://github.com/noahdunnagan/fsearch) by Noah Dunnagan.

Press a hotkey, type, and find any file by name, or search inside text and code files. FSearch for Mac is a native SwiftUI and AppKit app for macOS 14 and later. It is a graphical front end for the fsearch daemon, which does all the indexing and searching: the app bundles a pinned build of fsearch and talks to it over its socket API. This is an independent project and is not affiliated with fsearch or its author.

> There is no screenshot yet. Run the app, or follow [Tutorial: your first search](docs/tutorial-first-search.md), to see the panel.

## Features

- Launcher panel on ⌥Space (configurable), with file icons, match highlighting and the folder in grey.
- Search by name, search inside text and code files, or find definitions.
- Query filters such as `ext:`, `in:`, `type:`, `size:` and `mtime:`. Type `?` for the cheat sheet.
- Recent files when the query is empty. Reopen the panel within 60 seconds to resume.
- Actions: open, open at a line in your editor, reveal, Quick Look, copy, open with, move to Trash, and drag a result out.
- Four-step onboarding, with a warning if another launcher holds your hotkey.
- App commands in the panel: type `settings` (or `prefs`) to get to Settings.
- Settings for the hotkey, the editor for content results, Open FSearch at login, and an in-app uninstall ("Remove Background Helper and Data…").
- A quiet menu-bar reminder when Full Disk Access is off, and a Help menu with Report an Issue… (a pre-filled GitHub report without paths or queries).
- Debug mode with Index Details, a local Search Log and timings.
- Updates through Sparkle, once a release is signed, shown as a quiet menu-bar reminder.
- Works alongside the fsearch CLI: it never stops or replaces a daemon it did not start.

## Requirements

- macOS 14 (Sonoma) or later, Apple silicon or Intel.
- Full Disk Access is optional but lets FSearch for Mac index the whole disk.

## Install

FSearch for Mac is unreleased: nothing has been published yet, and 0.1.0 will be the first release. When it is, download the DMG from the [Releases](https://github.com/domfahey/fsearch-app/releases) page and drag FSearch to Applications.

Until then, build from source. See [Development](#development). For step-by-step setup, see [Install FSearch for Mac](docs/install.md). To remove the app, see [Uninstall FSearch for Mac](docs/uninstall.md).

## Quick start

1. Open FSearch for Mac and follow the four onboarding steps.
2. Press ⌥Space and start typing. Press ↵ to open the selected file, or ⌘↵ to reveal it in Finder.
3. Below the results, choose **Search inside files** or **Find definitions** to change what the query searches. Type `?` alone to see the query syntax.

For a guided walk, see [Tutorial: your first search](docs/tutorial-first-search.md). For every key, see [Keyboard shortcuts](docs/reference/keyboard-shortcuts.md).

## Documentation

The [documentation hub](docs/README.md) links everything. Common starting points:

- [Tutorial: your first search](docs/tutorial-first-search.md)
- [Query syntax](docs/reference/query-syntax.md) and [Keyboard shortcuts](docs/reference/keyboard-shortcuts.md)
- [Troubleshooting](docs/reference/troubleshooting.md), the [FAQ](docs/reference/faq.md) and [Known limitations](docs/reference/limitations.md)
- [Update FSearch for Mac](docs/how-to/update.md)
- [Architecture](docs/architecture.md) and [Architecture Decision Records](docs/adr/README.md)
- [Privacy](docs/privacy.md), [Support](.github/SUPPORT.md), [Roadmap](docs/roadmap.md) and the [Changelog](CHANGELOG.md)

## How it works

The app bundles a universal (arm64 and x86_64) fsearch daemon and registers it as a background login item with SMAppService. The app talks to the daemon over a local Unix socket in `~/Library/Application Support/FSearch`. If a daemon is already answering, such as one installed by the fsearch CLI (`fsearch install --login`), the app uses it. For the full picture, see [Architecture](docs/architecture.md).

## Development

To build, test and submit a change, see [Contributing](CONTRIBUTING.md). It covers the prerequisites, every `make` task, the test tiers and the release scripts. Run `make help` to list the tasks.

The short version, from the repository root:

```sh
make daemon   # build the pinned fsearch daemon into Vendor/fsearch
make build    # generate the Xcode project and build the Debug app
make test     # run the FSearchKit tests
```

### Project layout

| Path | What it holds |
|---|---|
| `App/` | The app: panel, actions, daemon manager, onboarding, settings, debug views, updater |
| `AppTests/` | The app's unit tests, hosted in the app with fakes for the daemon, login items and Trash, and windows that never show (run in CI) |
| `AppUITests/` | End-to-end UI tests: the panel, keys, actions, Settings and the menu-bar item against a throwaway daemon (`make ui`, needs a GUI session) |
| `Packages/FSearchKit/` | Core logic and its unit and integration tests |
| `scripts/` | Daemon build, release, benchmark, UI smoke and docs check scripts |
| `bench/` | Benchmark baseline and notes |
| `docs/` | User and developer documentation, decision records, release runbook |

## Privacy

Your index and logs stay on your Mac. The app has no telemetry and makes no network requests of its own. The only network code is the Sparkle updater, which checks for updates once it is configured. See [Privacy](docs/privacy.md).

## Contributing

See [Contributing](CONTRIBUTING.md) and follow the [Code of Conduct](.github/CODE_OF_CONDUCT.md). For questions and bug reports, see [Support](.github/SUPPORT.md). To report a vulnerability, see [Security](.github/SECURITY.md).

## License

MIT. See [LICENSE](LICENSE). Bundled components are covered in [Third-party notices](THIRD_PARTY_NOTICES.md).

## Acknowledgements

- [fsearch](https://github.com/noahdunnagan/fsearch) by Noah Dunnagan. It does all the indexing and searching. FSearch for Mac is an independent front end and is not affiliated with it.
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus, for the global hotkey.
- [Sparkle](https://sparkle-project.org) for updates.

### Inspired by

- [Raycast](https://www.raycast.com): the panel's layout and keyboard-first flow follow Raycast's file search.
- [Everything](https://www.voidtools.com) by voidtools: instant search of a whole disk by file name, the experience this app aims to bring to the Mac.

Raycast and Everything are trademarks of their owners. FSearch for Mac is not affiliated with either and uses none of their code or assets.
