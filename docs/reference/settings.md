# Settings

This page lists the options in FSearch for Mac's Settings window.

Open **Settings…** from the menu-bar icon.

## Options

| Setting | Values | Default | What it does |
|---|---|---|---|
| Shortcut | Any key combination | ⌥Space | The global hotkey that shows and hides the panel. |
| Open content results in | Default app, or an installed editor | Default app | The editor that opens a matching line at its line number. See [Open results in your editor](../how-to/open-results-in-your-editor.md). |
| Open FSearch at login | On or off | Off | Opens the app when you log in, using a Login Item. Shows the real status: on, waiting for approval (with a button that opens Login Items), or off. A failure appears under the switch. |
| Debug mode | On or off | Off | Shows the debug dot, timings, Index Details and Search Log. Turning it off deletes the search log. See [Turn on debug mode](../how-to/turn-on-debug-mode.md). |

**Remove Background Helper and Data…** sits below the options. After you confirm, it removes the helper, the login item, the data and log folders (to the Trash) and the app's settings. See [Uninstall](../uninstall.md).

The same debug switch is in the menu as **Turn On Debug Mode** (⌥⌘D).

## Stored values

The app keeps its settings in its standard preferences file, `~/Library/Preferences/com.domfahey.fsearch.plist`. These are the keys it writes itself:

| Key | Type | Meaning |
|---|---|---|
| `editor` | String | The chosen editor: `vscode`, `cursor`, `zed`, `sublime`, `bbedit` or `xcode`. Empty means the default app. |
| `debugMode` | Bool | Whether debug mode is on. |
| `onboarded` | Bool | Whether the welcome window is finished. While false, the menu shows **Finish Setup…**. |
| `skippedFullDiskAccess` | Bool | Whether you pressed **Skip for now** on the Full Disk Access step. |
| `dismissedFullDiskAccessReminder` | Bool | Whether you chose **Don't Remind Me** on the menu-bar Full Disk Access reminder shown after skipping. |
| `recentPaths` | List of strings | The files you opened from the panel, newest first. Up to 16 are kept. The empty panel shows up to 8 that still exist. |

The shortcut is stored by the [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) library under its own key.

## Fixed behavior

These are not settings:

- The panel is 680 by 460 points and opens on the screen where the mouse is.
- Reopening the panel within 60 seconds resumes your last query.
- Name searches ask for 50 results.
- The search log keeps 10,000 searches.

## See also

- [Change the hotkey](../how-to/change-the-hotkey.md)
- [Open results in your editor](../how-to/open-results-in-your-editor.md)
- [Turn on debug mode](../how-to/turn-on-debug-mode.md)
