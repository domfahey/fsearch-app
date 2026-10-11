# 0009. Coverage gates (FSearchKit and app unit tests at 90%)

Date: 2026-10-10
Status: Accepted

## Context

Tests should fail when coverage drops, but a gate has to be a number CI can measure the same way every time. FSearchKit holds the pure logic. The app target holds glue, which needs fakes, and a little code that only touches macOS.

The UI tests also cover app code, but they need a logged-in GUI session and nobody using the Mac, so hosted CI runners cannot run them.

## Considered options

- One combined gate for the app, from unit and UI tests together. CI cannot run the UI tests, so the gate could not run there.
- A 90% gate for the app's unit tests from the start. AppTests alone reached about 84% then, so it would have failed.
- No gates. Coverage would slip with no warning.
- A 90% gate for FSearchKit and an 80% gate for the app's unit tests alone, with thin system adapters left out of the app number. This was the first choice; the app gate is now 90% too (below).

## Decision

- CI fails if FSearchKit line coverage is below 90% (`scripts/coverage.sh --kit-only --min 90`).
- CI fails if app line coverage from AppTests alone is below 90% (`scripts/coverage.sh --unit-only --min 90`). It started at 80% and was raised to 90% on 2026-10-11, once AppTests reached about 92%.
- The app number leaves out the thin system adapters listed in `scripts/coverage.sh` (the pass-throughs to `SMAppService`, `NSWorkspace`, `Process`, Trash, app activation and Sparkle). Tests replace these with fakes, as [ADR 0007](0007-test-seams-inert-test-host-and-test-mode.md) describes.
- The full app number, from the unit and UI tests together, comes from `make coverage` on a hands-off GUI session. It is not a CI gate.

## Consequences

- `make ci` runs both gates locally.
- A new system call needs a seam and a fake, or its lines count against the 90% floor.
- Both floors are now 90%. Views are tested through their accessibility tree in the inert host (see `AppTests/Support/Accessibility.swift`), so view code counts too.
- Adding a function to the exclusion list in `scripts/coverage.sh` is a reviewed decision. The script reports an excluded function that no longer exists.

See [Contributing](../../CONTRIBUTING.md).
