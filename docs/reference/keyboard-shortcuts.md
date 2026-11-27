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
| ↵ | Open the selected file in its default app (or reveal it in Finder if it is an app, script, installer, internet location, executable or another type that would run or install something: see [Files that reveal instead of open](#files-that-reveal-instead-of-open). Use ⌘K → **Open** to launch it). For a matching line from a content or definition search, open it at that line in your chosen editor. On a "Use … with…" row, switch to that search. On the **FSearch Settings** row, open Settings and hide the panel. The panel hides after a file opens or is revealed. |
| ⌘↵ | Reveal the selected file in Finder, and hide the panel |
| ⌘Y | Quick Look the selected file. While the preview is up, ↑ and ↓ (with no modifiers) move the selection and the preview follows; ⌘ or ⇧ arrows go to Quick Look. Press ⌘Y again to close it. |
| ⌘⇧C | Copy the selected file's path |
| ⌘K | Open the actions menu under the selected file |
| ⌘/ | Open or close the FSearch menu. See [FSearch menu (⌘/)](#fsearch-menu-) below. |
| ⌘1 to ⌘9 | Open the first to ninth file result (revealing launchables, as with ↵). It never lands on a command or "Use … with…" row. |
| Esc | Clear the query. If the query is already empty, remove the **Inside files** or **Definitions** chip. If there is no chip, hide the panel. |
| Backspace on an empty field | Remove the **Inside files** or **Definitions** chip |

Notes:

- ⌘Y, ⌘K and ⌘⇧C work with Caps Lock on.
- The ⌘ shortcuts and ↵ do nothing with ⌃ or ⌥ held too: ⌘⌃Y is not ⌘Y.
- Keys that act on a result do nothing when there are no rows.
- ⌘1 to ⌘9 open the first nine file results only.
- Copy Path leaves the panel open. Open, Reveal and the actions that go to another app hide it.
- When another app opens the panel (an `fsearch://` URL, or FSearch being opened again while it runs), ↵, ⌘↵ and ⌘1 to ⌘9 are ignored for 0.5 s. This stops a keypress meant for the other app from opening the selected file. The hotkey and the menu never start this wait. Other keys work at once.

## Files that reveal instead of open

↵, ⌘1 to ⌘9 and a double-click show these in Finder instead of opening them, because opening would run or install them. ⌘K → **Open** still opens them. A matching line opened in your chosen editor is not affected.

- Apps and executables: `.app`, `.command`, `.tool`, `.terminal`, `.workflow`, and any file with no extension that is executable.
- Scripts: `.scpt`, `.scptd`, `.applescript`.
- Installers and disk images: `.pkg`, `.mpkg`, `.dmg`.
- Internet locations: `.webloc`, `.inetloc`, `.fileloc`.
- Profiles, panes and plugins: `.mobileconfig`, `.prefpane`, `.saver`, `.qlgenerator`, `.osax`.
- Actions and shortcuts: `.action`, `.shortcut`.
- Java programs: `.jar`, `.jnlp`.

## App commands

Type at least the first two letters of one of a command's keywords (listed below — matching checks keywords, not the row title) to show its row under the file results, just above the "Use … with…" rows. Command rows appear only in name search, not in Inside files or Definitions mode. ↵ still opens the top file; select the command row first (↓, or click it). With no matching files, the command row is first.

| Type | Row | ↵ does |
|---|---|---|
| `settings`, `preferences` or `prefs` (or the start, such as `set` or `pre`) | FSearch Settings | Open Settings |

## With the mouse

| Action | Result |
|---|---|
| Click a row | Select it |
| Double-click a row | Open it (or reveal it if launchable, as with ↵) |
| Drag a row | Drag the file into Finder, Mail or another app |
| Click a "Use … with…" row | Switch to Search inside files or Find definitions |
| Click the FSearch Settings row | Open Settings |
| Click the gear (**FSearch**) at the left of the footer | Open or close the FSearch menu |

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

## FSearch menu (⌘/)

Press ⌘/ or click the gear (**FSearch**) at the left of the panel's footer. The menu opens over the results, with the app version at the top and a **Search for actions…** field at the bottom. It is separate from the ⌘K actions menu, which acts on the selected file.

| Row | Shortcut | Does |
|---|---|---|
| Send Feedback | | Open a pre-filled GitHub bug report (versions, chip and daemon state; never paths or queries) |
| Manual | | Open the FSearch Help pages |
| Keyboard Shortcuts | | Open this page |
| Changelog | | Open the changelog |
| About FSearch | | Show the About window |
| Settings… | ⌘, | Open Settings |
| GitHub (under **Community**) | | Open the project on GitHub |
| Discussions (under **Community**) | | Open GitHub Discussions |
| Quit FSearch | ⌘Q | Quit the app |

Every row except Quit hides the panel.

| Key | Action |
|---|---|
| Type | Filter the rows by name or keyword. The first match is selected. For example, `chan` finds Changelog, `bug` finds Send Feedback, `docs` finds Manual, and `exit` finds Quit FSearch. |
| ↑ or ⌃P, ↓ or ⌃N | Move the selection. It wraps at both ends: from the last row to the first, and from the first row to the last. |
| ↵ | Run the selected row |
| Esc | Clear the filter. If it is already empty, close the menu. The panel stays up. |
| ⌘/ | Close the menu |

The mouse works too: point at a row to select it, click to run it, and click outside the menu to close it.

## Menu-bar menu

| Item | Shortcut | Does |
|---|---|---|
| Update Available… | | Shown when a scheduled update is waiting; opens the update window |
| Turn On Full Disk Access… or Grant Full Disk Access to fsearch… | | Shown whenever Full Disk Access is off (unless you skipped and dismissed the reminder). Opens Full Disk Access in System Settings and, for FSearch's own helper, restarts the helper automatically once granted |
| Don't Remind Me | | Shown below the Full Disk Access item only if you skipped Full Disk Access during onboarding; hides the reminder |
| Search… | | Open the panel |
| Index Details… | | Debug mode only |
| Search Log… | | Debug mode only |
| Turn On Debug Mode or Turn Off Debug Mode | ⌥⌘D | Toggle [debug mode](../how-to/turn-on-debug-mode.md). A menu-item shortcut: it works while the menu is open, not as a global hotkey. |
| Finish Setup… | | Shown until the welcome window is done |
| Help | | A submenu: FSearch Help, Keyboard Shortcuts, Query Syntax, Changelog, Privacy, GitHub, Discussions, and **Report an Issue…**, which opens a pre-filled GitHub bug report (versions, chip and daemon state; never paths or queries) |
| About FSearch | | |
| Settings… | | See [Settings](settings.md) |
| Check for Updates… | | Shown only in builds with updates configured |
| Quit FSearch | | |

When an update is waiting, **Update Available…** is the first item, above any warning line. When something needs attention, the menu starts with a warning line and, for some problems, a **Fix…** button. See [Troubleshooting](troubleshooting.md).

## See also

- [Query syntax](query-syntax.md)
- [Change the hotkey](../how-to/change-the-hotkey.md)
