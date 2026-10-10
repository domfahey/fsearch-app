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

## v2: search window

- A search window alongside the panel, on the same engine.
- Clickable filter chips.
- Sorting.
- File previews.

## Later

- Maybe a Raycast extension that uses the same fsearch daemon.

## Upstream fsearch changes

FSearch for Mac depends on the [fsearch](https://github.com/noahdunnagan/fsearch) daemon. The app needs these changes upstream:

- A version in the daemon's status, so the app can detect a mismatched daemon.
- Agent ownership, so the app's helper can take over from a stray daemon.
- A daemon-wide query log, so the debug log can cover searches from every client.
