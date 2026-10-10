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

### Updates

Shown only in releases that can update themselves (a build without the update signing key hides it, and so does the **Check for Updates…** menu item).

| Setting | Values | Default | What it does |
|---|---|---|---|
| Automatically check for updates | On or off | Asked on the second launch | Lets FSearch check for a new version in the background. Sparkle stores this itself (`SUEnableAutomaticChecks`). |
| Check Now | Button | | Checks immediately. Disabled while a check is already running. |

When a background check finds an update and FSearch isn't the front app, it doesn't open a window. The menu-bar icon changes to a down-arrow circle and the menu gets **Update Available…** at the top; choose it to see the update.

**Remove Background Helper and Data…** sits below the options. After you confirm, it removes FSearch's own helper and its login item, moves the log folder to the Trash, and clears the app's settings. It moves the data folder (the index) to the Trash only if FSearch's helper was running the daemon and the fsearch CLI's login agent is not installed. Otherwise the folder stays and the window says why. See [Uninstall](../uninstall.md).

The same debug switch is in the menu-bar menu as **Turn On Debug Mode** (⌥⌘D). ⌥⌘D is a menu-item shortcut: it works while the menu is open, not as a global hotkey.

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
- Name searches ask for 50 results. See [Known limitations](limitations.md#the-50-result-cap).
- The search log keeps 10,000 searches.

## See also

- [Change the hotkey](../how-to/change-the-hotkey.md)
- [Open results in your editor](../how-to/open-results-in-your-editor.md)
- [Turn on debug mode](../how-to/turn-on-debug-mode.md)
