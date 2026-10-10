# Use FSearch with the fsearch CLI

You can have the [fsearch](https://github.com/noahdunnagan/fsearch) command-line tool and FSearch for Mac on the same Mac. They share one search daemon.

## How they coexist

- If a daemon already answers on the socket, the app uses it. This is the case when you installed the CLI and ran its login agent (`fsearch install --login`).
- The app never stops or replaces a daemon it did not start.
- If the CLI's login agent is installed (the app only checks that the file `~/Library/LaunchAgents/mt.nd.fsearch.plist` exists) but its daemon is briefly down, the app waits for it. It does not register a second daemon.
- Only when no daemon is around does the app register its own bundled helper as a login item.
- The app and the CLI use the same data folder, `~/Library/Application Support/FSearch`, and the same index and socket.

The app never changes anything in `~/Library/LaunchAgents`.

## Full Disk Access belongs to the daemon that runs

macOS grants Full Disk Access to a program. The daemon is the program that reads your disk, so the grant has to be on whichever daemon is running.

- If the app's own helper runs, grant access to FSearch.
- If your CLI daemon runs, grant access to your `fsearch` binary in System Settings, then restart that daemon.

In the welcome window, the Full Disk Access step says which case applies. See [Grant Full Disk Access](grant-full-disk-access.md).

## Restarting

Restart Daemon in debug mode's Index Details window restarts only a daemon the app registered. For a CLI daemon it just checks again. Restart a CLI daemon from the CLI.

## Switching to the app's helper

To let the app run its own helper, stop and uninstall the CLI daemon first using the CLI's own commands. Then quit and reopen FSearch. See the [fsearch README](https://github.com/noahdunnagan/fsearch) for those commands.

See [ADR 0003](../adr/0003-never-take-over-a-daemon-the-app-did-not-start.md) for why the app behaves this way.
