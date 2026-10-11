# Query syntax

This page lists the query syntax that FSearch for Mac passes to the fsearch daemon. Type `?` alone in the panel for a short version.

## Plain words

Words match file names. A word also matches if any parent folder name matches it, so `projects invoice` can find `invoice.pdf` inside a folder called `projects`. Matching is fuzzy and ignores case, and typos are tolerated in longer words.

Prefixes and suffixes change how one word matches:

| Write | Meaning |
|---|---|
| `word` | Fuzzy match |
| `'word` | The name contains the text exactly, as one unbroken run. Case is ignored, and it can be part of a longer word. |
| `^word` | The name starts with it |
| `word$` | The name ends with it |
| `!word` | Drop a file if its name or any parent folder name contains the text. Case is ignored. |

Use one prefix or suffix per word. They do not combine: `^word$` is read as a "starts with" match for the text `word$`, not as an exact name.

Case folding covers the letters A to Z only, so `é` does not match `É`. For accented letters stored in the other Unicode form, see [Accented names](#accented-names) and [Known limitations](limitations.md).

A word with `/` in it is split at the slashes, so `src/main` is two words. The daemon tracks up to eight positive words; extra ones are ignored.

The panel asks for up to 50 results. In name search, add `limit:` to ask for more or fewer; the panel shows at most 1000.

### Accented names

Names that Mac apps write, such as `Café`, store accented letters in decomposed form (NFD), while typing gives the composed form (NFC). The daemon compares bytes, so the two forms don't match. When a name query has an accented letter, the panel also searches its other form and merges the results, so `café` finds both kinds of name. Case folding still covers A to Z only.

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
| `limit:` | How many results to ask for, in name search and in searches inside files. The panel shows at most 1000. | `limit:200` |

An unknown `type:` or `kind:` value shows an error under the search field.

### Typing a filter

While you are still typing the last word of a filter, the panel waits: it sends nothing, so daemon errors don't flash up as you type. The last word counts as unfinished when it is:

- a filter key with nothing after the colon: `foo size:`
- the start of a `type:` or `kind:` value: `type:c`, `kind:fi`, or a comma with nothing after it: `type:code,`
- a range cut short: `size:1mb..`, `size:>`, `mtime:<`

While you are adding to the query you searched last, in the same mode, the results already on screen stay up. If you replaced the query (select all and paste) or switched modes, the panel clears the results instead, because they answer a different search. Typing a space ends the wait, and the query is then sent as typed.

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

In the **Inside files** and **Definitions** modes, a word is a filter only when it has a value right after the colon. A bare key is text, so `kind: Deployment` or `limit: 10` searches for that text. To search for text that looks like a filter, such as `ext:rs`, put a double quote at the start of the word: `"ext:rs"`.

Content searches have a time budget of 250 ms. If it runs out, you may see partial results.

### What content search covers

Content search reads text and code files only. It looks at files that meet all of these rules:

- The file is under your home folder.
- The file is 1 MB or smaller.
- The file is plain text or code, judged by its extension (for example `.swift`, `.py`, `.md`, `.txt`, `.json`, `.csv`, `.log`). A file with no extension counts only if it is 256 KB or smaller. Minified `.min.js` files and `package-lock.json` are left out.
- No folder on its path is one of the skipped folders.

It does not read PDF, Word (`.docx`) or Pages files, or any other binary format. It also skips folders named `node_modules`, `.git`, `build`, `dist`, `vendor`, `Library`, `cache` or `caches`, plus many other dependency and cache folders, and everything inside `.app` bundles (and similar bundles such as `.framework` and `.photoslibrary`).

File names are different. Name search covers every file the index holds, whatever its type.

## Examples

| Query | Finds |
|---|---|
| `invoice` | Files with "invoice" in the name |
| `invoice ext:pdf` | PDFs named like invoice |
| `type:image mtime:<7d` | Images changed this week |
| `size:>100mb kind:file` | Large files |
| `report 'final !draft` | Names with "report" and the exact text "final" (even inside a longer word), and no "draft" in the name or any parent folder |
| `^readme ext:md` | Markdown files whose names start with "readme" |
| `kind:dir in:~/Developer proj` | Folders named like proj under Developer |
| `grep:"TODO fix" ext:rs` | Rust files containing the text `TODO fix` |
| `regex:fn\s+main ext:rs` | Rust files with `fn main` |
| `sym:SearchModel` | Where `SearchModel` is defined |

## See also

- [Keyboard shortcuts](keyboard-shortcuts.md)
- [Tutorial: your first search](../tutorial-first-search.md)
- [Known limitations](limitations.md)
- [Troubleshooting](troubleshooting.md)
