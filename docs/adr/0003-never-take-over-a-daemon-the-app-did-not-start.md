# 0003. Never take over a daemon the app did not start

Date: 2026-10-10
Status: Accepted

## Context

Some people already run the fsearch CLI with its own login agent (`mt.nd.fsearch`). Two daemons cannot serve the same data folder: one holds the lock on the socket. If the app stopped or replaced a daemon it did not start, it would break that setup. It would also move Full Disk Access to a different binary without telling the user.

If the app's own helper starts while another daemon holds the socket, the helper exits normally. A LaunchAgent that always restarts would then relaunch it forever.

## Considered options

- Always use the app's own helper, and stop any other daemon. This breaks an existing CLI setup and moves Full Disk Access without warning.
- Never register the helper if the CLI is installed. This is simpler but leaves the app with no daemon when the CLI's agent is not installed.
- Use whichever daemon answers, and register the helper only when none does. This is the choice below.

## Decision

At launch, the app decides with `DaemonPlan.decide`:

1. If a daemon answers on the socket, use it.
2. Otherwise, if the app's own helper is already registered and enabled, use that.
3. Otherwise, if the CLI's login agent plist exists, use the CLI's daemon, even if it is briefly down. The app prefers that to asking you to approve a second daemon.
4. Otherwise, if the helper is waiting for approval, say so and do not register it again.
5. Otherwise, ping again for three seconds in case a daemon is only restarting. If none answers, register the bundled helper.

The app re-registers only a daemon it registered itself. For any other daemon, "restart" checks again (see the update note for the case where nothing answers).

The helper's LaunchAgent uses `KeepAlive` with `SuccessfulExit` set to false. It is relaunched only after a crash, never after a normal exit.

The app only checks that the CLI's plist exists. It never changes `~/Library/LaunchAgents`.

## Consequences

- The CLI and the app coexist, sharing one index and one data folder.
- Full Disk Access belongs to whichever daemon runs, and the setup window says which.
- If a stray daemon holds the socket, the app's helper stays quiet instead of fighting it.
- The app does not take over from a stray daemon. The pinned fork has a version of this for a daemon launched by a login agent (see the update note), but the app itself never stops a daemon it did not start.
- Switching from the CLI daemon to the app's helper is a manual step.

See [Use FSearch with the fsearch CLI](../how-to/use-with-the-fsearch-cli.md).

## Update note

Four refinements landed after this ADR was accepted while keeping the never-take-over invariant intact:

- When the CLI's login agent plist (`mt.nd.fsearch.plist`) exists and nothing answers immediately, the app now waits up to 10 seconds (`DaemonPlan.recheckWindow(cliAgentInstalled: true)`) before falling back to registering its bundled helper, so a stale leftover plist no longer leaves the app without a daemon.
- Daemon ownership is verified by combining the connected control-socket peer's code signature via `PeerIdentifier` (`LOCAL_PEERTOKEN`) with `socket.lock` via `SocketHolder` (checking the live process path and, outside the app bundle, its team code signature) through `DaemonPlan.holder`, where `other` wins if either says `other`, rather than relying solely on `SMAppService` status (see [ADR 0017](0017-trust-only-a-same-user-daemon-socket.md)).
- The pinned daemon build (fork commit `d26cf78`, see [ADR 0010](0010-pin-the-daemon-to-a-fork-commit.md)) includes `ba100f4`, which lets a daemon launched by a login agent (it checks `XPC_SERVICE_NAME`) stop a stray daemon and take the socket lock. That commit exists only on the `domfahey/fsearch` fork, not in upstream `noahdunnagan/fsearch` (v0.2.2 still lets the loser give way). It is the daemon's behavior, not the app stopping a daemon; the app still never takes over a daemon it did not start.
- "Restart" for a daemon the app does not own is not always a bare check. `DaemonPlan.restartAction` returns `.start` when nothing answers and the daemon is not ours, which registers the bundled helper. It returns `.refreshOnly` when another daemon answers. Separately, the app restarts its own helper once after an app update changes the helper binary (`DaemonPlan.helperUpdate`, `DaemonManager.restartIfUpdated`).
