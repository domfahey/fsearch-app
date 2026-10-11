# 0007. Test seams, inert test host and test mode

Date: 2026-10-10
Status: Accepted

## Context

The app calls things that change your Mac: it registers login items with `SMAppService`, opens files and Trash items through `NSWorkspace`, starts the Sparkle updater, registers a global hotkey, and shows windows that take focus. A test that runs any of these could change the login items of the Mac it runs on, or steal the keyboard from the person using it.

The app's unit tests (AppTests) run inside the app as a test host, so the real app code starts unless something stops it.

## Considered options

- Run the unit tests against the real services. This changes the tester's Mac and needs a hands-off GUI session.
- Test only the logic that has no system calls, and leave the app untested. Most of the app's behavior is glue, so this leaves most of it unchecked.
- Put every system call behind a small protocol (a seam), give the tests fakes, and make the test host do nothing visible. This is the choice below.

## Decision

- **Seams.** System services sit behind protocols in `App/Support/Seams.swift` (for example `HelperService`, `LoginItemService` and `DaemonControl`). The real adapters live in `App/Support/SystemSeams.swift`. Tests use the fakes in `AppTests/Support/Fakes.swift`.
- **Test mode.** The flag `-FSEARCH_SOCKET <path>` points the app at a throwaway daemon. In test mode the app never touches `SMAppService`, never shows onboarding and keeps its search log beside that daemon. The UI tests and `scripts/ui-smoke.sh` use it.
- **Inert host.** When the app hosts AppTests, it detects the XCTest environment and runs as test mode with a socket nobody listens on. It starts no helper, hotkey, onboarding or Sparkle. Windows are ordered in invisibly, and the app never activates itself. `TestHostSafetyTests` checks that no window is key or visible after the app's window paths run.

## Consequences

- AppTests are safe to run while you work, and they run in CI.
- New code that calls macOS must go behind a seam, and its thin adapter is the one part that tests do not run. [ADR 0009](0009-coverage-gates.md) excludes those adapters from the app coverage number.
- Tests that need real focus or keystrokes live in AppUITests, which need a hands-off GUI session and do not run in CI.
- The real registration path is covered only by the manual release steps in the [release runbook](../release-checklist.md).

See [ADR 0005](0005-tests-never-touch-the-real-index.md) and [Contributing](../../CONTRIBUTING.md).
