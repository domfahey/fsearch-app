# Tutorial: your first search

In this tutorial you will open the launcher, find a file by name, search inside files, find where something is defined, and use the actions menu. It takes about five minutes.

You need FSearch installed and set up. If you have not done that, follow [Install](install.md) first. The magnifying glass should be in your menu bar.

## 1. Open the launcher

Press the hotkey. The default is Option+Space (⌥Space).

A floating panel opens in the middle of your screen with the cursor in the search field. With an empty field it lists the last files you opened from the panel, under "Recent". On a fresh install the list is empty.

If nothing happens, see [Change the hotkey](how-to/change-the-hotkey.md). Another launcher, such as Raycast, may own ⌥Space.

You can also click the menu-bar icon and choose **Search…**.

## 2. Find a file by name

Type part of a file name, for example `invoice`. Results appear as you type. Each row shows the file icon, the name with your letters highlighted, and the folder in grey.

Matching is forgiving. You do not need the exact name or every letter.

Use the up and down arrow keys to move the selection. Press Return (↵) to open the selected file in its default app. The panel hides when the file opens.

Press the hotkey again. The file you just opened is now under "Recent" when the field is empty.

## 3. Reveal, preview and open by number

Type a name again, then try these on a result:

- ⌘↵ shows the file in Finder.
- ⌘Y shows a Quick Look preview. ↑ and ↓ move to the next file and the preview follows. Press ⌘Y again to close it. The panel stays open behind the preview.
- ⌘1 to ⌘9 opens the first to ninth file directly.

## 4. Search inside files

Type a word that appears in the text of some file, for example `TODO`.

Below the file results are two rows under "Use “TODO” with…". Press the down arrow until **Search inside files** is selected, then press Return. You can also click it.

A chip that says **Inside files** appears in the search field. Rows now show the matching line of text instead of the folder. The matched text is highlighted.

Press Return on a line to open that file. If you chose an editor in Settings, the file opens at that line. See [Open results in your editor](how-to/open-results-in-your-editor.md).

To narrow the search, add filters to the same field. For example, `TODO ext:swift` looks only in Swift files. The [query syntax reference](reference/query-syntax.md) lists every filter. Type `?` alone to see a short list in the panel.

## 5. Go back to file names

Press Escape. The first press clears the text. A second press removes the **Inside files** chip. A third press hides the panel.

You can also press Backspace in an empty field to remove the chip.

## 6. Find a definition

Type the name of a function or type from your own code. Select **Find definitions** and press Return. The chip now says **Definitions**, and rows show the lines that define that name.

## 7. Use the actions menu

Type a name, select a result, and press ⌘K. A menu opens with:

- Open
- Open With
- Reveal in Finder
- Quick Look
- Copy Path
- Copy File
- Open Folder in Terminal
- Move to Trash

Choose one with the mouse or the arrow keys. Actions that take you to another app, such as Open and Reveal in Finder, hide the panel. Quick Look, Copy Path and Copy File leave it open.

Move to Trash moves the file to the Trash and keeps the panel open. It has no direct shortcut.

You can also drag a result row into Finder, Mail or another app.

## 8. Hide the panel

Press Escape until the panel hides, or click outside it. If you reopen it within 60 seconds, it resumes with your last query and selection.

## Where to go next

- [Keyboard shortcuts](reference/keyboard-shortcuts.md)
- [Query syntax](reference/query-syntax.md)
- [Troubleshooting](reference/troubleshooting.md)
