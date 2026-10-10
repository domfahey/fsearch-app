# FAQ

This page answers common questions about FSearch for Mac.

## What is FSearch for Mac?

A menu-bar launcher for the [fsearch](https://github.com/noahdunnagan/fsearch) file-search daemon by Noah Dunnagan. fsearch builds and serves the index. This app is the panel, the setup and the actions.

## Which macOS versions work?

macOS 14 (Sonoma) and later, on Apple silicon and Intel.

## Does it send my files or searches anywhere?

No. The index and logs stay on your Mac. The app makes no network requests of its own, except that the updater checks for new versions in builds that have updates configured. See [Privacy](../privacy.md).

## Does it replace Spotlight?

No. It is a separate launcher with its own hotkey. It searches file names and file contents.

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

## Is it on the Mac App Store?

No. It is distributed as a signed, notarized download. See [ADR 0006](../adr/0006-not-on-the-mac-app-store.md).

## How do I update it?

Builds with updates configured show **Check for Updates…** in the menu. Other builds do not.

## How do I remove it?

See [Uninstall](../uninstall.md).

## Why does the panel say "Starting search…" or "Indexing your disk…"?

"Starting search…" means the app cannot reach the fsearch daemon yet or it did not answer in time. "Indexing your disk… results will appear shortly" means the first index is still being built. Both clear by themselves. See [Troubleshooting](troubleshooting.md).

## Why is there a red line under the search field?

The daemon rejected your query, and the red text is its own message, for example about an unfinished regular expression. Fix the query. A filter you are still typing, like `size:` with no value, does not trigger it. See [Query syntax](query-syntax.md).

## Where do I report a bug or ask for a feature?

See [Support](../../.github/SUPPORT.md). For security problems, see [Security](../../.github/SECURITY.md).

## See also

- [Troubleshooting](troubleshooting.md)
- [Documentation hub](../README.md)
