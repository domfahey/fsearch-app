# 0003. Never take over a daemon the app did not start

Date: 2026-10-10
Status: Accepted

## Context

Some people already run the fsearch CLI with its own login agent (`mt.nd.fsearch`). Two daemons cannot serve the same data folder: one holds the lock on the socket. If the app stopped or replaced a daemon it did not start, it would break that setup. It would also move Full Disk Access to a different binary without telling the user.

If the app's own helper starts while another daemon holds the socket, the helper exits normally. A LaunchAgent that always restarts would then relaunch it forever.

## Decision

At launch, the app decides with `DaemonPlan.decide`:

1. If a daemon answers on the socket, use it.
2. Otherwise, if the app's own helper is already registered and enabled, use that.
3. Otherwise, if the CLI's login agent plist exists, use the CLI's daemon, even if it is briefly down. The app prefers that to asking you to approve a second daemon.
4. Otherwise, if the helper is waiting for approval, say so and do not register it again.
5. Otherwise, ping again for three seconds in case a daemon is only restarting. If none answers, register the bundled helper.

The app restarts only a daemon it registered itself. For any other daemon, "restart" just checks again.

The helper's LaunchAgent uses `KeepAlive` with `SuccessfulExit` set to false. It is relaunched only after a crash, never after a normal exit.

The app only checks that the CLI's plist exists. It never changes `~/Library/LaunchAgents`.

## Consequences

- The CLI and the app coexist, sharing one index and one data folder.
- Full Disk Access belongs to whichever daemon runs, and the setup window says which.
- If a stray daemon holds the socket, the app's helper stays quiet instead of fighting it.
- Taking over from a stray daemon is left as future work, and needs an upstream change so a daemon can mark itself agent-owned.
- Switching from the CLI daemon to the app's helper is a manual step.

See [Use FSearch with the fsearch CLI](../how-to/use-with-the-fsearch-cli.md).
