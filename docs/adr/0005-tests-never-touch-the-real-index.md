# 0005. Tests never touch the real index

Date: 2026-10-10
Status: Accepted

## Context

A test that talks to your real daemon could read your real files, change your index, or register a login item on the machine that runs it. The app also has a real daemon on developer Macs.

## Decision

- Integration tests run against a real fsearch daemon that the test starts itself, with a temporary `HOME` and `FSEARCH_ROOT` so it only sees test files. This is the same isolation the fsearch Rust tests use.
- The UI smoke test (`scripts/ui-smoke.sh`) also starts its own throwaway daemon. It launches the app with `-FSEARCH_SOCKET <path>` pointing at it.
- That flag turns on test mode. In test mode the app never touches `SMAppService`, never registers the login helper, and does not show the welcome window.
- The integration daemon cannot outlive its test run. `RealDaemon` starts it under an `sh` wrapper whose stdin is a pipe that only the test process holds. When the test process closes the pipe, exits or is killed, the wrapper stops the daemon (SIGTERM, then SIGKILL after 5 s) and removes the temporary `HOME`. As a backstop, the next run sweeps orphans: daemons from this repository's `Vendor/fsearch`, with no parent, whose `HOME` is under `/private/tmp/fsk-`. Any other daemon, including yours, is left alone.
- Unit tests use fakes: a scripted socket server for the client, and a fake backend for the search model.
- Test and debug work does not touch `~/Library/Application Support/FSearch`, `~/Library/LaunchAgents` or the real login items.

## Consequences

- Tests are safe to run on any Mac, including one with a working install.
- Tests need the built daemon in `Vendor/fsearch`, so `scripts/build-daemon.sh` runs first.
- The UI smoke test needs a logged-in GUI session and accessibility permission, so it does not run in CI.
- Test mode skips the real registration path, so that path is covered by the manual release checklist.

See [Contributing](../../CONTRIBUTING.md) and the [release checklist](../release-checklist.md).
