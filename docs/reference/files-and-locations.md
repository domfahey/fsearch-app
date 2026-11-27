# Files and locations

This page lists where FSearch for Mac and the fsearch daemon keep files on your Mac.

## Data folder

`~/Library/Application Support/FSearch`

This is the fsearch daemon's folder. The app and the fsearch CLI share it, so they share one index. It holds, among the daemon's other files:

| File | What it is |
|---|---|
| `fsearch.sock` | The socket the app uses to talk to the daemon. |
| `socket.lock` | Daemon lock and PID ownership metadata, checked alongside the connected peer's code signature (and used as a fallback if the peer's identity cannot be read). The [Data folder safety](troubleshooting.md#data-folder-safety-shows-a-problem) check verifies that `socket.lock`, `fsearch.sock` and the data folder itself are owned by your user and are not symbolic links. |
| `skipped` | Folders the daemon skipped while indexing (for example, protected folders while Full Disk Access is off), shown in Index Details under **Folders the index lacks (skipped)**. |
| `daemon.log` | The daemon's log, written by the fsearch CLI's daemon. The app's bundled `SMAppService` helper does not write `daemon.log` (its stderr is discarded; the FSearch app itself writes operational logs to the macOS unified log). Index Details shows the last 30 lines of `daemon.log` in debug mode when present. |

In debug mode, **Reveal Data Folder** in Index Details opens this folder.

## Logs

| Path | What it is |
|---|---|
| `~/Library/Logs/FSearch/searches.jsonl` | The search log, one JSON record per line. Only written while debug mode is on. Keeps the last 10,000 searches, none older than 7 days; the file is trimmed periodically. Its folder uses mode `0700`, the file uses mode `0600`, and both are excluded from Time Machine backups (see [Privacy](../privacy.md#debug-search-log)). Deleted when debug mode is turned off. |

Each record has the time, query, mode, result count, the daemon's time in microseconds, the round trip in milliseconds, and an error if any.

## Preferences

`~/Library/Preferences/com.domfahey.fsearch.plist`. See [Settings](settings.md).

## Inside the app

`FSearch.app/Contents/` holds:

| Path | What it is |
|---|---|
| `MacOS/FSearch` | The app. |
| `Helpers/fsearch` | The bundled fsearch daemon. |
| `Library/LaunchAgents/com.domfahey.fsearch.daemon.plist` | The login item that runs the helper as `fsearch serve`. |

The login item's label is `com.domfahey.fsearch.daemon`. It restarts the helper only after a crash (`KeepAlive` with `SuccessfulExit` false). A helper that exits normally, because another daemon holds the socket, is not restarted. See [ADR 0003](../adr/0003-never-take-over-a-daemon-the-app-did-not-start.md).

The app's bundle identifier is `com.domfahey.fsearch`. You see the login item under System Settings, General, Login Items & Extensions.

## The fsearch CLI's files

If you use the CLI's login agent, it lives at `~/Library/LaunchAgents/mt.nd.fsearch.plist`. The app only checks whether this file exists. It never edits it. See [Use FSearch with the fsearch CLI](../how-to/use-with-the-fsearch-cli.md).

## Removing everything

See [Uninstall](../uninstall.md).

## See also

- [Uninstall](../uninstall.md)
- [Privacy](../privacy.md)
