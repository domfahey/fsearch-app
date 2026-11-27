# Roadmap

This page lists what FSearch for Mac may do next. It is a plan, not a promise: items may change, move or be dropped, and none of them have dates.

## v1: launcher panel (unreleased, 0.1.0 is next)

Nothing has been released yet. Version 0.1.0 will be the first release. See the [Changelog](../CHANGELOG.md).

The launcher panel, opened with a shortcut. It searches by name, inside files, and for definitions. It includes the query filters, recent files, the actions menu, and debug mode.

Also in v1:

- App commands in the panel ("settings" opens Settings) and the panel's FSearch menu (`⌘/`).
- `fsearch://` URL scheme ([URL scheme](reference/url-scheme.md)) and the **Search Files** Shortcuts action ([Shortcuts](reference/shortcuts.md)).
- Accessibility support (Reduce Motion, Reduce Transparency, Increase Contrast, VoiceOver labels and traits, keyboard defaults) and localized String Catalogs (8 languages shipped).
- Open FSearch at login.
- An in-app uninstall button. See [Uninstall](uninstall.md).
- Unified logging.
- Report an Issue in the Help menu.

## Next

- Additional community translations beyond the initial 8 shipped languages (English, Japanese, Simplified Chinese, Spanish, French, German, Korean, and Brazilian Portuguese).

## v2: an Everything-style search window

A full window for when the panel isn't enough, modelled on [Everything](https://www.voidtools.com) by voidtools. It sits alongside the panel and uses the same engine ([ADR 0020](adr/0020-everything-style-search-window.md)).

Implemented on `main`:

- One search field over a dense results table that updates as you type, across the whole disk (Names, Inside Files, and Definitions modes).
- Columns for name, folder, size, kind and date modified. Sort by any column; resize and reorder columns.
- A status bar with the result count (noting when the 1,000-result cap is reached), selection count/size, and search time.
- Toggles for match case, whole word, regex and search-in-path, plus clickable `type:`, `kind:`, `ext:`, `in:`, `size:` and `mtime:` filter chips.
- Built-in quick filters and user-saved searches in a toggleable sidebar.
- Keyboard first: the same actions as the panel, multi-select, context menu, and drag out.
- A toggleable Quick Look preview pane and inside-file results with the matching line.
- More than one independent search window open at a time (`⌘N`).

Still planned once upstream `fsearch` adds server-side `offset` paging and sorting: scrolling past the 1,000-result cap across arbitrarily large result sets (`SearchWindowQuery.PageRequest` already reserves the `offset`/`limit`/`sort` contract).

## Later

- Maybe a Raycast extension that uses the same fsearch daemon.

## Upstream fsearch changes

FSearch for Mac depends on the [fsearch](https://github.com/noahdunnagan/fsearch) daemon. The app needs these changes upstream:

- A version in the daemon's status, so the app can detect a mismatched daemon.
- Agent ownership, so the app's helper can take over from a stray daemon.
- A daemon-wide query log, so the debug log can cover searches from every client.

## See also

- [Changelog](../CHANGELOG.md)
- [Contributing](../CONTRIBUTING.md)
- [Architecture](architecture.md)
