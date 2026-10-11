# FAQ

This page answers common questions about FSearch for Mac.

## What is FSearch for Mac?

A menu-bar launcher for the [fsearch](https://github.com/noahdunnagan/fsearch) file-search daemon by Noah Dunnagan. fsearch builds and serves the index. This app is the panel, the setup and the actions.

## Which macOS versions work?

macOS 14 (Sonoma) and later, on Apple silicon and Intel.

## Does it send my files or searches anywhere?

No. The index and logs stay on your Mac. The app makes no network requests of its own, except that the updater checks for new versions in builds that have updates configured. See [Privacy](../privacy.md).

## Does it replace Spotlight?

No. It is a separate launcher with its own hotkey. It searches file names, and the contents of text and code files.

## Does it launch apps?

Apps are files too. Typing "chrome" finds Google Chrome.app, and Return opens it. There is no separate app launcher.

## Why does it need Full Disk Access?

So the daemon can index folders macOS protects. Without it, search still works but misses them. See [Grant Full Disk Access](../how-to/grant-full-disk-access.md).

## Why does a background helper run?

It keeps the index up to date as files change, so results are instant. It starts when you log in. You can see it in System Settings, General, Login Items & Extensions.

## I already use the fsearch CLI. Will they clash?

No. If a daemon already answers, the app uses it and never replaces it. See [Use FSearch with the fsearch CLI](../how-to/use-with-the-fsearch-cli.md).

## Can I search inside files?

Yes. Type a word, then choose **Search inside files**, or type `grep:word`. See [Query syntax](query-syntax.md).

## How do I find where a function is defined?

Type the name and choose **Find definitions**, or type `sym:name`.

## Can I limit a search to a folder or file type?

Yes. Use `in:` and `ext:` or `type:`. See [Query syntax](query-syntax.md).

## Why doesn't it find text in my PDF?

Search inside files reads text and code files only. It does not read PDF, Word (`.docx`) or Pages files. FSearch still finds those files by name. See [What content search covers](query-syntax.md#what-content-search-covers).

## Why can't it find a file with an accent in its name?

Matching ignores case for the letters A to Z only, so `É` and `é` may not match. Accented names are found in both Unicode forms, so `café` finds a file that a Mac app stored in the other form. See [Known limitations](limitations.md#case-folding-and-accented-names).

## Why do I only see 50 results?

Name searches return up to 50 results. To get more, add `limit:`, such as `limit:200`. The panel shows at most 1000. You can also add words or filters such as `ext:` or `in:` to narrow the list. See [Known limitations](limitations.md#the-50-result-cap).

## Does it search external drives?

Probably not. The daemon treats `/Volumes`, where external drives mount, as a guarded folder and does not cross into other volumes. FSearch for Mac has not been tested with external drives, so treat them as unsupported. See [Known limitations](limitations.md).

## Which folders does search inside files skip?

It skips dependency, build and cache folders such as `node_modules`, `.git`, `build`, `dist`, `vendor` and `Library`, and the inside of `.app` bundles. Name search still finds those files. See [What content search covers](query-syntax.md#what-content-search-covers).

## Is it on the Mac App Store?

No. It is distributed as a signed, notarized download. See [ADR 0006](../adr/0006-not-on-the-mac-app-store.md).

## How do I update it?

Builds with updates configured check for new versions in the background and show **Update Available…** in the menu when one is ready. See [Update FSearch for Mac](../how-to/update.md).

## How do I remove it?

See [Uninstall](../uninstall.md).

## Why does the panel say "Starting search…" or "Indexing your disk…"?

"Indexing your disk… results will appear shortly" means the first index is still being built. It clears by itself. For "Starting search…", see [Troubleshooting](troubleshooting.md#starting-search-does-not-go-away).

## Why is there a red line under the search field?

The daemon rejected your query, and the red text is its own message, for example about an unfinished regular expression. Fix the query. A filter you are still typing, like `size:` with no value, does not trigger it. See [Query syntax](query-syntax.md).

## Where do I report a bug or ask for a feature?

See [Support](../../.github/SUPPORT.md). For security problems, see [Security](../../.github/SECURITY.md).

## Glossary

These words appear in the app and in these docs.

- **Daemon.** The fsearch program that builds the index and answers searches. It runs in the background.
- **Helper.** The copy of the daemon bundled inside FSearch for Mac. The app registers it so it runs in the background. In Index Details, **Restart Daemon** restarts it.
- **Login item.** The macOS entry that starts the helper when you log in. You see it in System Settings, General, Login Items & Extensions. **Open FSearch at login** is a separate login item for the app itself.
- **Owner and follower.** Index Details shows a **Role**. The owner is the daemon that writes the index. A follower reads an index that another daemon writes.

## See also

- [Known limitations](limitations.md)
- [Troubleshooting](troubleshooting.md)
- [Documentation hub](../README.md)
