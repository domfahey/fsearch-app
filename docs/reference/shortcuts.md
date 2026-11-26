# Shortcuts (App Intents)

FSearch for Mac provides a **Search Files** action for Apple Shortcuts and Spotlight. It queries the running `fsearch` daemon in the background without opening the launcher panel and returns the matching files so you can pass them directly to other Shortcuts actions.

## Search Files action

| Parameter | Values | Default | Meaning |
|---|---|---|---|
| **Query** | Any FSearch query | *(required)* | Words and [query syntax](query-syntax.md) filters (for example `invoice ext:pdf`, `in:~/Developer mtime:<7d`, or `regex:TODO`). |
| **Search In** | **File Names**, **Inside Files**, **Definitions** | **File Names** | Whether to match file and folder names, text inside files, or symbol definitions in code. **Inside Files** and **Definitions** work only after you turn them on in Settings (see [Searching inside files](#searching-inside-files)). |
| **Limit** | `1` to `1000` | `50` | Maximum number of files to return. An explicit `limit:` filter in **Query** overrides this (still capped at 1000). |

### Output

Returns a list of **Files** in FSearch's ranked order (deduplicated). You can connect the output straight to built-in Shortcuts actions such as **Open Files**, **Quick Look**, **Reveal File in Finder**, **Filter Files**, **Repeat with Each** or **Run Shell Script**.

## Searching inside files

**Inside Files** and **Definitions** are off for Shortcuts until you turn on **Allow Shortcuts to search inside files** in FSearch's Settings. The setting is off by default. While it is off, those modes fail with an error that says where to turn it on. So does a **File Names** query that contains a content filter (`grep:`, `content:`, `regex:`, `sym:` or `symbol:`). **File Names** searches without one always work.

**Why it's off by default:** FSearch has Full Disk Access, and the action runs in the background without showing anything. Any shortcut can run it, including one you imported or one started with the `shortcuts run` command. With content search on, a shortcut could search for text such as `BEGIN RSA PRIVATE KEY` and get back the files that contain it, even in folders the shortcut itself couldn't read. It could also learn what a file says by trying one search after another. Turn the setting on only if you trust every shortcut that uses **Search Files**.

Removing FSearch's background helper and data in Settings turns the setting off again.

## Spotlight and Siri phrases

- *Search files in FSearch*
- *Find files with FSearch*

## Notes

- **Runs in the background:** **Search Files** does not open the launcher panel or steal focus. If you want to open the interactive launcher pre-filled with a query from Shortcuts, use the **Open URLs** action with the [URL scheme](url-scheme.md) (`fsearch://search?q=…`).
- **Query rules:** Blank queries and content searches with no text pattern return an empty list. Line breaks and tabs are turned into spaces and control characters are removed. Accented file names match both composed (NFC) and decomposed (NFD) forms.
- **Returned files:** The action returns the matching files by location. FSearch doesn't load their contents into the result; the action that receives them opens them.
- **Daemon errors:** If the `fsearch` daemon is not running, times out, is still building its initial index, or rejects a filter, the action fails with a plain-English error message (the daemon's own message for rejected filters, or the same short error text recorded in the debug Search Log).

## See also

- [Query syntax](query-syntax.md)
- [URL scheme](url-scheme.md)
- [Keyboard shortcuts](keyboard-shortcuts.md)
