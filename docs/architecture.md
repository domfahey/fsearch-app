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
2. `refresh()` bumps a generation counter and cancels the previous in-flight task. Only the newest generation may publish, so a slow old answer is dropped. A blank query, the `?` cheat sheet, or a `grep:`/`sym:` with no value yet sends nothing.
3. `run` picks a backend. Plain name queries go to `names.search(q, limit: 50)`. A query with `grep:`, `regex:` or `sym:` in names mode, and the content and symbol modes, go to `content.grep(...)`. [`AppState`](../App/AppState.swift) creates two `DaemonClient`s, each with its own `LineSocket`, so a slow content search never queues behind name searches.
4. `DaemonClient` sends requests one at a time on a serial queue. Each request carries a fresh integer `id`, and the daemon echoes it in its reply. A call cancelled while queued never touches the socket. `LineSocket` writes the line and reads lines back until `replyIsFor(id, line)` accepts one: a line with a different id is a stale leftover and is dropped, while a line with no id or a null id is accepted so that decoding reports it properly. All of this happens within one timeout (5 s by default); a call that sees only stale lines fails with `.timeout` and closes the connection. If a reused connection was dropped it dials again once and resends; timeouts are not retried.
5. `decodeReply` turns the line into a `SearchReply` or `GrepReply`, and `SearchModel` publishes `items` and a `SearchPhase` (`results`, `indexing`, `failed`). A `failed` phase carries a `DaemonError`, and `UserMessage` turns it into the short text the panel shows (see [Troubleshooting](reference/troubleshooting.md)).

## Who owns the daemon

[`DaemonManager.start()`](../App/Daemon/DaemonManager.swift) asks `DaemonPlan.decide` ([`DaemonPlan.swift`](../Packages/FSearchKit/Sources/FSearchKit/DaemonPlan.swift)) with three facts: does something answer a ping, what is the status of our own helper, and is the CLI's agent plist (`~/Library/LaunchAgents/mt.nd.fsearch.plist`) present. The app only checks that the file exists; it never writes there.

- Something answers: use it (`useExisting`).
- Our helper is already enabled: just refresh (`refreshOwn`).
- A CLI agent is installed: ping again for 10 seconds (`cliRecheckWindow`), since its daemon may be restarting. If it still doesn't answer (a leftover plist from a failed install, or a deleted binary), fall back to the bundled helper.
- Our helper is waiting in Login Items: show `needsApproval` and do not register again.
- Otherwise ping again for 3 seconds (`recheckWindow`), then register the bundled helper.

The app never stops, replaces or takes over a daemon it didn't start. It owns the daemon (`ownsDaemon`) only when our helper is `.enabled` and no other process holds the socket. It reads the pid the daemon writes to `<dataDir>/socket.lock` and checks with `proc_pidpath` that the process runs from inside `Bundle.main` (`SocketHolder`). It never locks that file. This matters because, since fsearch ba100f4, a CLI agent's daemon makes our helper yield. Our login item is then still enabled, but the daemon answering is the CLI's.

Restart (`DaemonPlan.restartAction`) re-registers only a daemon the app owns: unregister, wait for the old daemon to stop answering, register. It leaves any other daemon that answers running and just refreshes status. When nothing answers and nothing is ours, it runs `start()` again, which rechecks first. One restart runs at a time, and callers arriving meanwhile wait for it. The panel spends at most 3 restarts per outage (`RestartBudget`), refilled when results arrive. Once they are spent, or a search times out, the state says the helper stopped answering, and the menu bar and panel show that instead of "Starting search…".

Our helper is also restarted once in two cases. After an app update, launchd keeps running the old helper binary, so the app compares the bundled helper's identity (build, size and modification time, stored as `helperIdentity`) with the one last seen running. After the menu's "Turn On Full Disk Access…", the daemon fixes its skip list at start, so the next time the app becomes active it restarts the helper if Full Disk Access is still off.

The plist uses `KeepAlive` with `SuccessfulExit` false. launchd relaunches the daemon after a crash, but not after a clean exit 0, which is how it quits when another daemon already holds the socket.

The bundled helper writes no `daemon.log`. An `SMAppService` agent plist is fixed inside the signed bundle, and launchd doesn't expand `~` in `StandardErrorPath`, so the plist can't name a per-user log file. The helper's stderr goes nowhere, and Index Details says so when the log is empty. The CLI's login agent writes its plist at install time with an absolute path, so its daemon does log. A fix needs the daemon itself to open a log file in its data folder (an upstream ask).

At launch, a second running copy of the app hands over to the first and quits. A copy run from a translocated path or a read-only volume (the DMG) offers to move itself to /Applications and quits, without registering the helper.

## Onboarding, errors and the menu bar

[`OnboardingLauncher`](../App/Onboarding/OnboardingLauncher.swift) shows a four-step window (welcome, helper, Full Disk Access, indexing; `OnboardingStep`) until `onboarded` is set, and starts the helper itself if the window is closed early. Each step checks a fact from the system or daemon (`canContinue`), not a button press. Full Disk Access can be skipped (`skippedFullDiskAccess`).

`DaemonManager.state` is `checking`, `running`, `indexing`, `needsApproval` or `failed`. [`MenuBarStatus`](../App/Errors/MenuBarStatus.swift) maps it, plus the skip flag, through `MenuBarWarning.evaluate` to the menu-bar symbol and a message. Failure and approval offer "Fix…", which opens Index Details; missing Full Disk Access is only a reminder. [`DaemonMessageLine`](../App/Errors/DaemonMessageLine.swift) shows the same problems in the panel and drives recovery checks and restarts.

## Debug mode

`debugMode` (menu item or Settings, `DebugMode.set`) adds Index Details and Search Log windows, an orange dot in the panel, and per-search timing. `SearchModel.onSearched` feeds `SearchLog` only while it is on; turning it off deletes the log and closes both windows.

## Test mode

Launch a Debug build with `-FSEARCH_SOCKET <path>` and `AppState.socketPath` uses that socket. Release builds ignore this flag and the XCTest environment variables (`LaunchOptions.testHooksCompiledIn`). In this mode the app never calls `SMAppService` (`ownStatus` is nil, `ownsDaemon` is false), never restarts anything, and skips onboarding. Tests supply the daemon themselves with a temporary `HOME` and `FSEARCH_ROOT`, so the real index, login items and `~/Library/Application Support/FSearch` are never touched.

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
