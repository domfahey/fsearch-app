# Privacy

FSearch for Mac is built to keep your files and searches on your Mac.

## What is indexed

The fsearch daemon builds an index of your files. The index has file names. For content search, the daemon also reads the text inside files so it can find matches in them.

The daemon can only index what macOS lets it read. See [Full Disk Access](#full-disk-access) below.

## Where it lives

- **The index and the daemon's files** are in `~/Library/Application Support/FSearch`. This folder is the daemon's data folder. It holds the index, the socket the app talks to, and the daemon's log.
- **The app's settings** are stored in macOS preferences (UserDefaults) for the app. They include your shortcut, your editor choice, debug mode, and onboarding progress.
- **Recent files** are the paths of the last files you opened from the panel. FSearch stores paths only, not file contents. It keeps up to 16 and shows up to 8.
- **The debug search log** is in `~/Library/Logs/FSearch/searches.jsonl`. See below.

## Debug search log

Debug mode is off by default. It is turned on in Settings, or with Turn On Debug Mode in the menu bar (⌥⌘D).

While debug mode is on, FSearch writes one line for each search it runs in the panel. Each line has the time, the query, the search mode, the number of results, and the timings. Your search text is in the log.

- The log is capped at 10,000 searches. Older ones are dropped.
- It only records searches from this app. It does not record searches from the fsearch CLI or other apps.
- Turning debug mode off deletes the log.
- Clear Log, in the Search Log window, empties it at any time.

## Nothing leaves your Mac

- The app has no telemetry and no analytics.
- The app does not send your files, file names, searches or logs anywhere.
- The app's dependencies are KeyboardShortcuts (the shortcut) and Sparkle (updates). Neither one sends your data.
- The only network request the app makes is the update check, and only once update signing keys are configured in a release build. Sparkle then reads the update feed at `https://domfahey.github.io/fsearch-app/appcast.xml` and downloads signed updates.

## Full Disk Access

macOS hides some folders, such as Desktop, Documents, Downloads, Mail, Messages and iCloud Drive, from apps that do not have Full Disk Access.

FSearch asks for Full Disk Access so the search daemon can index those folders too. The index stays on your Mac. You can skip this step. Search still works, but it will not find files in those protected folders. The daemon is the process that reads your files, so the permission belongs to the daemon.

You can remove the permission at any time in System Settings, under Privacy & Security, then Full Disk Access.

## Deleting your data

To remove the app, its background helper, its index, and its logs, follow [docs/uninstall.md](uninstall.md).

## Questions

For privacy questions, open an issue on the [GitHub repository](https://github.com/domfahey/fsearch-app/issues). For security problems, see [Security](../.github/SECURITY.md).
