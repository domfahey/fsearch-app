# Roadmap

This is a plan, not a promise. Items may change, move or be dropped. None of them have dates.

## v1: launcher panel (now)

The launcher panel, opened with a shortcut. It searches by name, inside files, and for definitions. It includes the query filters, recent files, the actions menu, and debug mode.

## Next

- App commands in the panel, with a Settings screen.
- Launch FSearch itself at login.
- An in-app uninstall button. Until then, see [docs/uninstall.md](docs/uninstall.md).
- Unified logging.
- A Report an Issue action in the app.
- Accessibility and localization.

## v2: an Everything-style search window

A full window for when the panel isn't enough, modelled on [Everything](https://www.voidtools.com) by voidtools. It sits alongside the panel and uses the same engine.

- One search field over a dense results table that updates as you type, across the whole disk.
- Columns for name, folder, size, kind and date modified. Sort by any column; resize and reorder columns.
- A status bar with the result count and search time.
- Toggles for match case, whole word, regex and search-in-path, plus the existing `ext:`, `in:`, `size:` and `mtime:` filters as clickable chips.
- Saved searches and filters you can switch between.
- Keyboard first: the same shortcuts and actions as the panel, multi-select, and drag out.
- A preview pane (Quick Look) and inside-file results with the matching line.
- More than one window open at a time.

This needs the daemon to return more than 50 results quickly, with paging. Scrolling through very large result sets may need upstream fsearch changes.

## Later

- Maybe a Raycast extension that uses the same fsearch daemon.

## Upstream fsearch changes

FSearch for Mac depends on the [fsearch](https://github.com/noahdunnagan/fsearch) daemon. The app needs these changes upstream:

- A version in the daemon's status, so the app can detect a mismatched daemon.
- Agent ownership, so the app's helper can take over from a stray daemon.
- A daemon-wide query log, so the debug log can cover searches from every client.
