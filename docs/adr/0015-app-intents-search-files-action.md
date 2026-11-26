# 0015. App Intents "Search Files" action

Date: 2026-11-24
Status: Accepted

## Context

People want to use FSearch results in Apple Shortcuts and Spotlight, for example to filter, open or process a list of files. The [URL scheme](0014-fsearch-url-scheme-opens-the-panel.md) only opens the panel, so it cannot return results.

## Considered options

- Drive the panel from a shortcut through the URL scheme. It returns nothing to the shortcut.
- A Shortcuts action that queries the daemon and returns the files. This is the choice below.
- Expose the daemon socket or CLI to shell scripts. Shortcuts can already run a shell script, but it needs the CLI installed and gives no typed result.

## Decision

Add `SearchFilesIntent` (`App/Intents/SearchFilesIntent.swift`) with a query, a mode (names, content or definitions) and a limit of 1 to 1000. It also appears as an `AppShortcut` with Spotlight and Siri phrases.

- It runs in the background (`openAppWhenRun = false`). The panel does not open.
- It makes its own `DaemonClient` on the app's socket path. It does not use the panel's connection, so it does not cancel or race a search in the panel ([ADR 0004](0004-two-socket-connections-and-latest-wins.md)). A `Mutex`-guarded `backendFactory` lets tests supply a fake, so tests never touch the real daemon ([ADR 0005](0005-tests-never-touch-the-real-index.md)).
- The search logic is `ShortcutSearch` in FSearchKit. It reuses `SearchURL.sanitize`, merges accented file names, dedupes and ranks paths, and caps results at 1000.
- It does not write to the debug Search Log. That log records the panel's searches.
- It returns `[IntentFile]`.

## Consequences

- Shortcuts can chain a search into Open Files, Quick Look or Filter Files. See [Shortcuts](../reference/shortcuts.md).
- Unit tests cover the intent without a daemon, as with the panel.
- Intent searches do not appear in the Search Log, so they are harder to debug.
- Open security question: the action returns files as `IntentFile` from an app that shares the helper's Full Disk Access, so a shortcut can reach protected files the shortcut's author could not read directly. Gating this is being addressed in a follow-up.

## Amendment

2026-11-26: Content search via Shortcuts is now opt-in. This answers the open security question above. The action refuses **Inside Files**, **Definitions** and any content filter (`grep:`, `content:`, `regex:`, `sym:`, `symbol:`) with an error, unless the user turns on **Allow Shortcuts to search inside files** in Settings (`allowShortcutsContentSearch`, off by default). `ShortcutSearch.readsFileContents` decides what counts. File name searches always work. The unattended action, which any shortcut can run, therefore cannot probe file contents with FSearch's Full Disk Access until the user allows it. Removing the helper and data in Settings turns the setting off. See [Shortcuts](../reference/shortcuts.md#searching-inside-files).
