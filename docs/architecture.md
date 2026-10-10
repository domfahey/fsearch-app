# Architecture

This page explains how FSearch for Mac is put together and how a keystroke becomes a result.

FSearch for Mac is a menu-bar launcher (`LSUIElement`, no Dock icon) in front of the `fsearch` Rust daemon. The app draws the UI and talks to the daemon; the daemon owns the index.

## The pieces

1. **The app** (`App/`, SwiftUI and AppKit). It shows the panel, menu bar item, onboarding, settings and debug windows.
2. **The daemon**, `fsearch serve`. The app bundles it at `Contents/Helpers/fsearch` and registers it as an `SMAppService` login agent ([`LaunchAgent.plist`](../App/Resources/LaunchAgent.plist), label `com.domfahey.fsearch.daemon`). If a daemon already answers (for example the CLI's login agent), the app uses that one instead.
3. **The socket**, `~/Library/Application Support/FSearch/fsearch.sock`. One JSON object per line in each direction, over a Unix stream socket. Requests are `search` (the default op), `grep`, `status`, `ping` and `save`; every reply carries `ok`, and `{"ok": false, "error": ...}` becomes a `DaemonError` ([`Wire.swift`](../Packages/FSearchKit/Sources/FSearchKit/Wire.swift)).

```text
 +-------------------------- FSearch.app ---------------------------+
 |  SearchView -> SearchModel (generation, cancel)                   |
 |                  |                  |                             |
 |        names: DaemonClient   content: DaemonClient   (own sockets)|
 |                  |  LineSocket  |                                 |
 +------------------|--------------|---------------------------------+
                    v              v
        ~/Library/Application Support/FSearch/fsearch.sock
                    |  JSON lines: {"id":1,"q":"..."} <-> {"ok":true,...}
                    v
          fsearch serve  (bundled helper, or a CLI daemon already there)
                    |
                    v
          name index + content index on disk
```

The app logs through `os.Logger` (subsystem `com.domfahey.fsearch`, see `App/Support/Log.swift`); see [Collecting logs](reference/troubleshooting.md#collecting-logs).

## FSearchKit and the App target

[`Packages/FSearchKit`](../Packages/FSearchKit) holds everything that can be tested without a UI: the wire types and `decodeReply`, `LineSocket`, `DaemonClient`, `SearchModel`, `QuerySplit`/`QuerySyntax`, `DaemonPlan`, `RestartBudget`, `MenuBarWarning`, onboarding rules, `Recents`, `SearchLog`, key handling (`PanelKeys`) and row layout (`PanelRows`). It has no dependencies. The `FSearch` target in [`project.yml`](../project.yml) is the glue: windows, `SMAppService`, Sparkle, the global shortcut, and file actions. Put new logic in the package and keep the App code thin.

## One keystroke

1. [`SearchView`](../App/Panel/SearchView.swift) changes `model.query`; `.onChange` calls `SearchModel.refresh()`. A mode change calls it directly.
2. `refresh()` bumps a generation counter and cancels the previous in-flight task. Only the newest generation may publish, so a slow old answer is dropped. A blank query, the `?` cheat sheet, a half-typed filter, or a `grep:`/`sym:` with no value yet sends nothing. Published results are tagged with the query and mode they answer; `resultsAreCurrent` is false until they match the box, so the panel doesn't act on a stale row.
3. `run` picks a backend. Plain name queries go to `names.search(q, limit: 50)`; the request leaves the JSON limit out when the query has its own `limit:`. A query with an accented letter also searches its other Unicode normal form, and the hits are merged by path. A query with `grep:`, `regex:` or `sym:` in names mode, and the content and symbol modes, go to `content.grep(...)`. [`AppState`](../App/AppState.swift) creates two `DaemonClient`s, each with its own `LineSocket`, so a slow content search never queues behind name searches.
4. `DaemonClient` sends requests one at a time on a serial queue. Each request carries a fresh integer `id`, and the daemon echoes it in its reply. A call cancelled while queued never touches the socket. `LineSocket` writes the line and reads lines back until `replyIsFor(id, line)` accepts one: a line with a different id is a stale leftover and is dropped, while a line with no id or a null id is accepted so that decoding reports it properly. All of this happens within one timeout (5 s by default); a call that sees only stale lines fails with `.timeout` and closes the connection. If a reused connection was dropped it dials again once and resends; timeouts are not retried.
5. `decodeReply` turns the line into a `SearchReply` or `GrepReply`, and `SearchModel` publishes `items` and a `SearchPhase` (`results`, `indexing`, `failed`). A `failed` phase carries a `DaemonError`, and `UserMessage` turns it into the short text the panel shows (see [Troubleshooting](reference/troubleshooting.md)).

## Who owns the daemon

[`DaemonManager.start()`](../App/Daemon/DaemonManager.swift) asks `DaemonPlan.decide` ([`DaemonPlan.swift`](../Packages/FSearchKit/Sources/FSearchKit/DaemonPlan.swift)) with three facts: does something answer a ping, what is the status of our own helper, and is the CLI's agent plist (`~/Library/LaunchAgents/mt.nd.fsearch.plist`) present. The app only checks that the file exists; it never writes there.

- Something answers: use it (`useExisting`).
- Our helper is already enabled: just refresh (`refreshOwn`).
- A CLI agent is installed: use it, even if it is restarting.
- Our helper is waiting in Login Items: show `needsApproval` and do not register again.
- Otherwise ping again for 3 seconds (`recheckWindow`), then register the bundled helper.

The app restarts only a daemon it registered (`ownsDaemon`: not test mode and our helper is `.enabled`). Restart means unregister, wait for the old daemon to stop answering, register. For any other daemon, "restart" just refreshes status. The panel spends at most 3 restarts per outage (`RestartBudget`), refilled when results arrive. The plist uses `KeepAlive` with `SuccessfulExit` false: launchd relaunches the daemon after a crash, but not after a clean exit 0, which is how it quits when another daemon already holds the socket.

## Onboarding, errors and the menu bar

[`OnboardingLauncher`](../App/Onboarding/OnboardingLauncher.swift) shows a four-step window (welcome, helper, Full Disk Access, indexing; `OnboardingStep`) until `onboarded` is set, and starts the helper itself if the window is closed early. Each step checks a fact from the system or daemon (`canContinue`), not a button press. Full Disk Access can be skipped (`skippedFullDiskAccess`).

`DaemonManager.state` is `checking`, `running`, `indexing`, `needsApproval` or `failed`. [`MenuBarStatus`](../App/Errors/MenuBarStatus.swift) maps it, plus the skip flag, through `MenuBarWarning.evaluate` to the menu-bar symbol and a message. Failure and approval offer "Fix…", which opens Index Details; missing Full Disk Access is only a reminder. [`DaemonMessageLine`](../App/Errors/DaemonMessageLine.swift) shows the same problems in the panel and drives recovery checks and restarts.

## Security notes

The daemon runs with the Full Disk Access you grant it and answers over a local socket in your user account's data folder. At present the daemon does not verify which program is on the other end of that socket, so other programs that run as the same macOS user may be able to use it. The index is also stored in that folder as ordinary files readable by your account. This matches the trust boundary in [SECURITY.md](../.github/SECURITY.md): a program already running as you can read your files anyway, but the daemon's Full Disk Access reaches folders that program could not otherwise open. Peer verification is an open request to the upstream fsearch project; the app does not work around it.

## Debug mode

`debugMode` (menu item or Settings, `DebugMode.set`) adds Index Details and Search Log windows, an orange dot in the panel, and per-search timing. `SearchModel.onSearched` feeds `SearchLog` only while it is on; turning it off deletes the log and closes both windows.

## Test mode

Launch the app with `-FSEARCH_SOCKET <path>` and `AppState.socketPath` uses that socket. In this mode the app never calls `SMAppService` (`ownStatus` is nil, `ownsDaemon` is false), never restarts anything, and skips onboarding. Tests supply the daemon themselves with a temporary `HOME` and `FSEARCH_ROOT`, so the real index, login items and `~/Library/Application Support/FSearch` are never touched.

## Tests and benchmarks

- **FSearchKit unit and integration tests**, [`Packages/FSearchKit/Tests/FSearchKitTests`](../Packages/FSearchKit/Tests/FSearchKitTests): `FakeDaemon` is a scripted socket server; `RealDaemon` runs `Vendor/fsearch serve` with a temp `HOME` and `FSEARCH_ROOT` ([`IntegrationTests.swift`](../Packages/FSearchKit/Tests/FSearchKitTests/IntegrationTests.swift)). `RealDaemon` has a watchdog: the daemon runs under a small `sh` wrapper that blocks on a pipe held by the test process, so when the test process exits or crashes, the wrapper stops the daemon and deletes the temp directory. At the start of a run it also sweeps orphaned fixture daemons left by hard-killed runs (see [ADR 0005](adr/0005-tests-never-touch-the-real-index.md)). Run `make test`, or `swift test` in the package.
- **App unit tests**, [`AppTests/`](../AppTests): hosted tests for the app's own logic (DaemonManager, AppState, onboarding, panel input, file actions, menus). System side effects (SMAppService, NSWorkspace, Process, Trash) sit behind small seams in [`App/Support/`](../App/Support), which the tests replace with fakes; the test host starts nothing (no helper, hotkey, onboarding or updater).
- **End-to-end UI tests**, [`AppUITests/PanelUITests.swift`](../AppUITests/PanelUITests.swift), run by [`scripts/ui-smoke.sh`](../scripts/ui-smoke.sh). The script starts a throwaway daemon in a temporary `HOME` and passes its socket to the app as `FSEARCH_SOCKET`. Every synthesized keystroke first checks that FSearch is frontmost and the search field has focus. They need a GUI session and don't run in CI.
- **Coverage**: [`scripts/coverage.sh`](../scripts/coverage.sh) runs both suites and merges the results.
- **Benchmarks**, `FSearchBench` in the package, run by [`scripts/bench.sh`](../scripts/bench.sh) against a temporary daemon; see [`bench/README.md`](../bench/README.md).

## See also

- [Architecture Decision Records](adr/README.md)
- [Files and locations](reference/files-and-locations.md)
- [Contributing](../CONTRIBUTING.md)
