# Open results in your editor

Results from searching inside files can open at the matching line. You choose the editor in Settings.

## Choose an editor

1. Click the menu-bar icon and choose **Settings…**.
2. Open **Open content results in:**.
3. Pick an editor.

The list shows **Default app** and only the supported editors installed on your Mac.

## Supported editors

FSearch asks macOS (LaunchServices) to open the editor with a link, the same way a web page opens an app. It never runs the editor's command-line tool itself. So the editor runs as its own app and does not get the Full Disk Access you gave FSearch.

| Editor | What FSearch asks macOS to open |
|---|---|
| Visual Studio Code | `vscode://file/path:line` |
| Cursor | `cursor://file/path:line` |
| Zed | `zed://file/path:line` |
| Sublime Text | `subl://open?url=file://path&line=line` |
| BBEdit | `x-bbedit://open?url=file://path&line=line` |
| Xcode | The file itself, opened with Xcode. Xcode has no documented open-at-line link, so it opens the file but doesn't jump to the line. |

VS Code and Cursor have been checked on a real Mac. Zed, Sublime Text and BBEdit have not been tested against a real install yet. If one of them does not work for you, please report it (see [Support](../../.github/SUPPORT.md)).

## What opens when

- A content result (a matching line) opens in your chosen editor at that line (Xcode: the file, without the line).
- A file-name result always opens in its default app.
- With **Default app**, or if the editor is not installed, every result opens in its default app.
- If the editor can't open it, FSearch opens the file in its default app instead. The file opens, but not at the line.
- ↵ on something that would run rather than open (an app, a script such as a `.command` file, an installer, a web location, or a file with no extension that can run) shows it in Finder instead. To launch it, press ⌘K and choose **Open**. The footer says "⌘K → Open to launch" when this applies.
- If the file was moved or deleted since the search, the panel shows an error and stays open.

If opening at the line opens the file only, see [Troubleshooting](../reference/troubleshooting.md).
