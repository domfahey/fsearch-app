# Troubleshooting

Use this page to match what FSearch for Mac shows you to a cause and a fix. If your symptom is not here, see [Support](../../SUPPORT.md).

For most problems, turn on [debug mode](../how-to/turn-on-debug-mode.md) first. Index Details shows what the daemon is doing.

## "Starting search…" does not go away

The app cannot reach the search daemon. It restarts the daemon it registered itself, up to three times per outage. A daemon you started from the CLI is only re-checked, not restarted.

1. Wait a few seconds. A restarting daemon usually answers soon.
2. Look at the menu-bar icon. If it shows a warning, open the menu and choose **Fix…** to open Index Details.
3. Check **Login Items**: System Settings, General, Login Items & Extensions. FSearch should be on.
4. In Index Details, press **Restart Daemon**, and read the end of `daemon.log`.
5. If you use the CLI daemon, restart it from the CLI.

## "Indexing your disk… results will appear shortly"

The fsearch daemon is building its first index. Results appear when it finishes, usually within a minute or so. The panel keeps checking by itself. Searching works as soon as the index is ready.

If it never finishes, open Index Details and check that the entry count grows.

## The menu-bar icon shows a warning

The icon changes to a magnifying glass with an exclamation mark. Open the menu to read the message.

| Message | What to do |
|---|---|
| The search helper isn't running | Choose **Fix…**, then **Restart Daemon**. |
| The search helper needs your approval | Choose **Fix…**, then **Open Login Items Settings** and turn FSearch on. See below. |
| Full Disk Access is off, so some files won't be found | See [Grant Full Disk Access](../how-to/grant-full-disk-access.md). This one has no **Fix…** button. |

## Files in Desktop, Documents, Downloads, Mail or iCloud Drive are missing

macOS hides these folders until you allow Full Disk Access. See [Grant Full Disk Access](../how-to/grant-full-disk-access.md). The "Folders the index lacks (skipped)" list in Index Details shows what was left out.

## The hotkey does nothing

Another app probably owns it. Pick a different shortcut in Settings. See [Change the hotkey](../how-to/change-the-hotkey.md). Meanwhile, use **Search…** in the menu.

## The login item needs approval

macOS asks you to approve background helpers. Open System Settings, General, Login Items & Extensions, and turn FSearch on. The welcome window and Index Details both have an **Open Login Items Settings** button. The app notices when you approve it.

## Opening a line opens the file instead

The file opens in its default app, not at the line, when:

- you left **Open content results in** on **Default app**;
- the chosen editor is gone, or its command failed (the app then falls back to the default app);
- the result is a file name, not a matching line. Only matching lines open at a line.

See [Open results in your editor](../how-to/open-results-in-your-editor.md). The Zed, Sublime Text and BBEdit paths are not tested on a real install yet.

## A query shows a red error line

The daemon rejected the query, for example an unfinished regular expression or an unknown `type:`. The panel shows the daemon's own message in red under the search field. Fix the query and results resume. See [Query syntax](query-syntax.md).

A filter you are still typing, such as `foo size:` with nothing after the colon, does not search or show an error. The panel keeps the results it has until you finish the value or type a space.

## Other messages in the panel

These are the exact texts the panel shows when a search cannot return results.

| You see | Meaning | What to do |
|---|---|---|
| Starting search… | The app cannot reach the daemon yet, or it did not answer in time. | See [Starting search…](#starting-search-does-not-go-away). |
| Indexing your disk… results will appear shortly | The first index is still being built. | Wait. See [Indexing](#indexing-your-disk-results-will-appear-shortly). |
| Unexpected reply from the search daemon: *detail* | The daemon answered with something the app does not understand, for example `reply has no "hits"`. This usually means the app and the daemon are different versions. | Quit and reopen FSearch. If it persists, [report it](../../SUPPORT.md) with the detail text. |
| *The daemon's own message* (in red) | The daemon rejected the query. | Fix the query. |

In the debug-mode Search Log, a failed search is recorded as "Can't reach the search daemon", "The search daemon didn't answer in time", "The search index is still being built", or "The search daemon reported an error" (when the daemon gave no text).

## Nothing shows for a search inside files

- Add text after `grep:`, `regex:` or `sym:`. With nothing after the colon, no search runs.
- Content search needs the daemon's content index. In Index Details, check the content "Waiting to be indexed" count.

## Still stuck

Quit FSearch from the menu and open it again. Then see [Support](../../SUPPORT.md).

## See also

- [Turn on debug mode](../how-to/turn-on-debug-mode.md)
- [Files and locations](files-and-locations.md)
- [FAQ](faq.md)
