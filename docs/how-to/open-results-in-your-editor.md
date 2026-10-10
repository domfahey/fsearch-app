# Open results in your editor

Results from searching inside files can open at the matching line. You choose the editor in Settings.

## Choose an editor

1. Click the menu-bar icon and choose **Settings…**.
2. Open **Open content results in:**.
3. Pick an editor.

The list shows **Default app** and only the supported editors installed on your Mac.

## Supported editors

| Editor | Command FSearch runs |
|---|---|
| Visual Studio Code | `code -g path:line` |
| Cursor | `cursor -g path:line` |
| Xcode | `xed -l line path` |
| Zed | `cli path:line` |
| Sublime Text | `subl path:line` |
| BBEdit | `bbedit_tool +line path` |

Each command is the tool inside the editor's app bundle. For Xcode it is `/usr/bin/xed`.

VS Code, Cursor and Xcode have been checked on a real Mac. The Zed, Sublime Text and BBEdit paths have not been tested against a real install yet. If one of them does not work for you, please report it (see [Support](../../SUPPORT.md)).

## What opens when

- A content result (a matching line) opens in your chosen editor at that line.
- A file-name result always opens in its default app.
- With **Default app**, or if the editor is not installed, every result opens in its default app.
- If the editor's command fails, FSearch opens the file in its default app instead. The file opens, but not at the line.

If opening at the line opens the file only, see [Troubleshooting](../reference/troubleshooting.md).
