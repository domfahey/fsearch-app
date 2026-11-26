# Open results in your editor

Results from searching inside files and finding definitions can open at the matching line. You choose the editor in Settings.

## Choose an editor

1. Click the menu-bar icon and choose **Settings…**.
2. Open **Open content results in:**.
3. Pick an editor.

The list shows **Default app** and the supported editors installed on your Mac (a previously chosen editor that was later uninstalled stays shown as `<Editor> (not installed)` until you pick another).

## Supported editors

FSearch asks macOS (LaunchServices) to open the editor with a link, the same way a web page opens an app. It never runs the editor's command-line tool itself. So the editor runs as its own app and does not get the Full Disk Access you gave FSearch.

| Editor | What FSearch asks macOS to open |
|---|---|
| Visual Studio Code | `vscode://file/path:line` |
| Cursor | `cursor://file/path:line` |
| Zed | `zed://file/path:line` |
| Sublime Text | `subl://open?url=file:///path&line=line` |
| BBEdit | `x-bbedit://open?url=file:///path&line=line` |
| Xcode | The file itself, opened with Xcode. Xcode has no documented open-at-line link, so it opens the file but doesn't jump to the line. |

VS Code and Cursor have been checked on a real Mac. Zed, Sublime Text and BBEdit have not been tested against a real install yet. If one of them does not work for you, please report it (see [Support](../../.github/SUPPORT.md)).

## Editor signature check

Any app can claim an editor's bundle id, so before FSearch sends a file path to an editor it checks the app's code signature. The app must be validly signed by Apple's chain (Developer ID or App Store) with the editor's own identifier. For Visual Studio Code and Cursor the check also pins the developer's team. Xcode must be signed by Apple itself. For Zed, Sublime Text and BBEdit the team is not pinned yet.

If an installed editor fails the check, FSearch does not send it the path. It opens the file in the default app and shows "Not opening in *Editor*: its code signature isn’t the genuine app’s. Opened with the default app." in the panel footer. A copy of an editor that you re-signed yourself, or one built from source, fails the check too. To stop the message, set **Open content results in** to **Default app**.

## What opens when

- A content or definition result (a matching line) opens in your chosen editor at that line when the editor registers its URL scheme (the panel footer shows **Open at line ↵**). For Xcode, or an installed editor whose URL scheme isn't registered with LaunchServices, FSearch opens the file in that chosen editor without jumping to the line.
- A file-name result always opens in its default app.
- With **Default app**, or if the chosen editor is not installed, every result opens in its default app.
- If LaunchServices reports an error opening with the editor, FSearch falls back to the file's default app (without jumping to the line), and shows an error in the footer if the default app also refuses to open it.
- ↵ on something that would run rather than open (an app, a script such as a `.command` file, an installer, a web location, or a file with no extension that can run) shows it in Finder instead — except for content/definition hits opened in your chosen installed editor, which do not execute the script. To launch it, press ⌘K and choose **Open**. The footer says "⌘K → Open to launch" when this applies.
- If the file was moved or deleted since the search, the panel shows an error and stays open.

If opening at the line opens the file only, see [Troubleshooting](../reference/troubleshooting.md).
