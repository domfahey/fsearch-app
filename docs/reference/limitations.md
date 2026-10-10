# Known limitations

This page lists what FSearch for Mac does not do well yet, so you can tell a known limit from a bug.

## What search inside files covers

Search inside files reads plain-text and code files only. It reads a file only if all of these are true:

- The file is under your home folder.
- The file is 1 MB or smaller.
- The extension marks it as text or code, such as `.swift`, `.py`, `.md`, `.txt`, `.json` or `.csv`. A file with no extension counts only if it is 256 KB or smaller.
- No folder on its path is skipped. Skipped folders include `node_modules`, `.git`, `build`, `dist`, `vendor`, `Library`, caches and the inside of `.app` bundles.

PDF, Word (`.docx`) and Pages files are not read. They are still found by name. See [What content search covers](query-syntax.md#what-content-search-covers).

## Case folding and accented names

Name search ignores case for the letters A to Z only. It does not fold case for other letters, such as `É` and `é`, so they may not match.

Accented names are found in both forms. macOS can store an accented letter as one character or as a letter plus a combining mark. When a name query has an accented letter, the panel also searches the other form and merges the results. So `café` finds a file that a Mac app stored in either form.

## The 50-result cap

Name searches return up to 50 results. Add `limit:` to ask for more or fewer, for example `invoice limit:200`. The panel shows at most 1000 results. In a search inside files, `limit:` limits how many files are returned. To see fewer, narrower results, add words or filters such as `ext:` and `in:`.

## The 250 ms budget for content search

A search inside files stops reading files after 250 ms. When that happens, you may see only some of the matches. Add a filter such as `ext:` or `in:` so the daemon has fewer files to read.

## Other users and processes on your Mac

The daemon's socket accepts connections from any process that runs as your user. FSearch does not add its own check on top of that. See [Privacy](../privacy.md).

## External drives

External drives are untested. The daemon treats `/Volumes` as a guarded folder and does not cross into other volumes, so files on an external drive are probably not indexed.

## Editors

Opening a result at a line works with VS Code, Cursor and Xcode on a real Mac. Zed, Sublime Text and BBEdit are untested. If one fails, FSearch opens the file in its default app. See [Open results in your editor](../how-to/open-results-in-your-editor.md).

## Full Disk Access and the helper

Which program macOS lists for the bundled helper (the app or the helper itself) is not yet confirmed. Follow the on-screen steps in setup, and see [Grant Full Disk Access](../how-to/grant-full-disk-access.md) if protected folders are missing.

## Accessibility and localization

FSearch has not had an accessibility pass, so VoiceOver labels and keyboard navigation in Settings are incomplete. The app is in English only.

## See also

- [Query syntax](query-syntax.md)
- [Troubleshooting](troubleshooting.md)
- [FAQ](faq.md)
- [Roadmap](../roadmap.md)
