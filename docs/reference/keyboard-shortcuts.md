# Keyboard shortcuts

This page lists every keyboard shortcut in FSearch for Mac.

## Global

| Key | Action |
|---|---|
| ⌥Space (default) | Show or hide the launcher panel. You can change it in Settings. See [Change the hotkey](../how-to/change-the-hotkey.md). |

## In the panel

| Key | Action |
|---|---|
| ↑ or ⌃P | Move the selection up |
| ↓ or ⌃N | Move the selection down |
| ↵ | Open the selected file in its default app. For a line from a content search, open it at that line in your chosen editor. On a "Use … with…" row, switch to that search. The panel hides after a file opens. |
| ⌘↵ | Reveal the selected file in Finder, and hide the panel |
| ⌘Y | Quick Look the selected file. Press ⌘Y again to close the preview. |
| ⌘⇧C | Copy the selected file's path |
| ⌘K | Open the actions menu for the selected file |
| ⌘1 to ⌘9 | Open the first to ninth file result. It never lands on a "Use … with…" row. |
| Esc | Clear the query. If the query is already empty, remove the **Inside files** or **Definitions** chip. If there is no chip, hide the panel. |
| Backspace on an empty field | Remove the **Inside files** or **Definitions** chip |

Notes:

- ⌘Y, ⌘K and ⌘⇧C work with Caps Lock on.
- Keys that act on a result do nothing when there are no rows.
- ⌘1 to ⌘9 open the first nine file results only.
- Copy Path leaves the panel open. Open, Reveal and the actions that go to another app hide it.

## With the mouse

| Action | Result |
|---|---|
| Click a row | Select it |
| Double-click a row | Open it |
| Drag a row | Drag the file into Finder, Mail or another app |
| Click a "Use … with…" row | Switch to Search inside files or Find definitions |

## In the actions menu (⌘K)

The menu has no key equivalents of its own. Choose an entry with the mouse or the arrow keys and Return.

| Entry | Does | Hides the panel |
|---|---|---|
| Open | Open in the default app, or at the line for content results | Yes |
| Open With | Choose from up to 12 apps that can open the file | Yes |
| Reveal in Finder | Show in Finder | Yes |
| Quick Look | Preview | No |
| Copy Path | Copy the full path as text | No |
| Copy File | Copy the file itself, to paste in Finder or Mail | No |
| Open Folder in Terminal | Open Terminal in the file's folder (or the folder itself) | Yes |
| Move to Trash | Move the file to the Trash | No |

If an action fails, the panel stays up (or comes back) and shows the error in its footer for a few seconds.

## Menu-bar menu

| Item | Shortcut | Does |
|---|---|---|
| Search… | | Open the panel |
| Index Details… | | Debug mode only |
| Search Log… | | Debug mode only |
| Turn On Debug Mode or Turn Off Debug Mode | ⌥⌘D | Toggle [debug mode](../how-to/turn-on-debug-mode.md) |
| Finish Setup… | | Shown until the welcome window is done |
| About FSearch | | |
| Settings… | | See [Settings](settings.md) |
| Check for Updates… | | Shown only in builds with updates configured |
| Quit FSearch | | |

When something needs attention, the menu starts with a warning line and, for some problems, a **Fix…** button. See [Troubleshooting](troubleshooting.md).

## See also

- [Query syntax](query-syntax.md)
- [Change the hotkey](../how-to/change-the-hotkey.md)
