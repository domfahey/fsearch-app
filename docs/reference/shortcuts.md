# Shortcuts (App Intents)

FSearch for Mac provides a **Search Files** action for Apple Shortcuts and Spotlight. It queries the running `fsearch` daemon in the background without opening the launcher panel and returns the matching files so you can pass them directly to other Shortcuts actions.

## Search Files action

| Parameter | Values | Default | Meaning |
|---|---|---|---|
| **Query** | Any FSearch query | *(required)* | Words and [query syntax](query-syntax.md) filters (for example `invoice ext:pdf`, `in:~/Developer mtime:<7d`, or `regex:TODO`). |
| **Search In** | **File Names**, **Inside Files**, **Definitions** | **File Names** | Whether to match file and folder names, text inside files, or symbol definitions in code. |
| **Limit** | `1` to `1000` | `50` | Maximum number of files to return. An explicit `limit:` filter in **Query** overrides this (still capped at 1000). |

### Output

Returns a list of **Files** in FSearch's ranked order (deduplicated). You can connect the output straight to built-in Shortcuts actions such as **Open Files**, **Quick Look**, **Reveal File in Finder**, **Filter Files**, **Repeat with Each** or **Run Shell Script**.

## Spotlight and Siri phrases

- *Search files in FSearch*
- *Find files with FSearch*

## Notes

- **Runs in the background:** **Search Files** does not open the launcher panel or steal focus. If you want to open the interactive launcher pre-filled with a query from Shortcuts, use the **Open URLs** action with the [URL scheme](url-scheme.md) (`fsearch://search?q=…`).
- **Query rules:** Blank queries and content searches with no text pattern return an empty list. Line breaks and tabs are turned into spaces and control characters are removed. Accented file names match both composed (NFC) and decomposed (NFD) forms.
- **Daemon errors:** If the `fsearch` daemon is not running, is still building its initial index, or rejects a filter, the action fails with the same plain-English error message shown in the panel.

## See also

- [Query syntax](query-syntax.md)
- [URL scheme](url-scheme.md)
- [Keyboard shortcuts](keyboard-shortcuts.md)
