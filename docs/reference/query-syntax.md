# Query syntax

This page lists the query syntax that FSearch for Mac passes to the fsearch daemon. Type `?` alone in the panel for a short version.

## Plain words

Words match file names. Matching is fuzzy and ignores case, and typos are tolerated in longer words.

Prefixes and suffixes change how one word matches:

| Write | Meaning |
|---|---|
| `word` | Fuzzy match |
| `'word` | Exact match |
| `^word` | The name starts with it |
| `word$` | The name ends with it |
| `!word` | The name does not contain it |

A word with `/` in it is split at the slashes, so `src/main` is two words. The daemon tracks up to eight positive words; extra ones are ignored.

The panel asks for up to 50 results.

## Filters

A filter is `key:value`. Keys are lowercase and case-sensitive. A word that starts with a known key and a colon is a filter, not a name word.

| Filter | Meaning | Example |
|---|---|---|
| `ext:` | Extensions, comma separated, with or without a dot | `ext:rs,md` |
| `type:` | A kind of file: `code`, `doc`, `image`, `video`, `audio`, `archive`, `font`, `app`. Comma separated. | `type:image` |
| `kind:` | `file` (`f`), `dir` (`folder`, `d`) or `link` (`symlink`, `l`) | `kind:dir` |
| `in:` | Only under this folder. `~` means your home folder. | `in:~/Developer` |
| `size:` | A size range | `size:>10mb` |
| `mtime:` or `modified:` | A modified-time range | `mtime:<7d` |
| `re:` | Regular expression on the file name, ignoring case | `re:^main\.` |
| `path:` | Regular expression on the full path, ignoring case | `path:src/.*test` |
| `limit:` | A result limit, passed to the daemon | `limit:20` |

An unknown `type:` or `kind:` value shows an error under the search field.

### Typing a filter

While the last word is a filter key with nothing after the colon, such as `foo size:`, the panel waits. It sends nothing and keeps the results already on screen until you type a value or a space. This avoids a flash of daemon errors while you type. A space after the colon (`foo size: `) ends the wait, and the empty filter is then sent as typed.

### Ranges

`size:` and `mtime:` take one of these forms:

| Form | Meaning |
|---|---|
| `>x` or `>=x` | At least x |
| `<x` or `<=x` | At most x |
| `a..b` | From a to b |
| `x` | Exactly x |

Sizes use `b`, `k`/`kb`, `m`/`mb`, `g`/`gb` or `t`/`tb` (decimal, so 1mb is one million bytes).

Ages use `s` (seconds), `m` or `min` (minutes), `h`, `d` (days, the default), `w`, `mo` and `y`. `mtime:<7d` means modified in the last 7 days. A bare age such as `mtime:3d` means 3 to 4 days ago, like `find -mtime`.

### Quoting

Wrap a value that has spaces in double quotes: `in:"~/My Stuff"`. Quotes group words so the space does not split them.

## Searching inside files

These keys make the daemon search file contents and return matching lines:

| Key | Meaning |
|---|---|
| `grep:text` or `content:text` | Literal text |
| `regex:pattern` | Regular expression |
| `sym:name` or `symbol:name` | Definitions of a function, type or similar |

You can type one in the normal search field, or pick **Search inside files** or **Find definitions** from the "Use … with…" rows. Both do the same thing.

In content and definition searches, filters pick which files are searched, and the rest of the text is the pattern. So `TODO ext:swift in:~/Developer` searches for `TODO` inside Swift files under `~/Developer`. If you use a `grep:` key more than once, the last one wins. A content key with nothing after the colon does not search yet.

Content searches have a time budget of 250 ms.

## Examples

| Query | Finds |
|---|---|
| `invoice` | Files with "invoice" in the name |
| `invoice ext:pdf` | PDFs named like invoice |
| `type:image mtime:<7d` | Images changed this week |
| `size:>100mb kind:file` | Large files |
| `report 'final !draft` | Names with "report" and the exact word "final", without "draft" |
| `^readme ext:md` | Markdown files whose names start with "readme" |
| `kind:dir in:~/Developer proj` | Folders named like proj under Developer |
| `grep:"TODO fix" ext:rs` | Rust files containing the text `TODO fix` |
| `regex:fn\s+main ext:rs` | Rust files with `fn main` |
| `sym:SearchModel` | Where `SearchModel` is defined |

## See also

- [Keyboard shortcuts](keyboard-shortcuts.md)
- [Tutorial: your first search](../tutorial-first-search.md)
- [Troubleshooting](troubleshooting.md)
