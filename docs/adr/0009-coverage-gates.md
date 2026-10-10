# 0009. Coverage gates (FSearchKit 90%, app unit tests 80%)

Date: 2026-10-10
Status: Accepted

## Context

Tests should fail when coverage drops, but a gate has to be a number CI can measure the same way every time. FSearchKit holds the pure logic. The app target holds glue, which needs fakes, and a little code that only touches macOS.

The UI tests also cover app code, but they need a logged-in GUI session and nobody using the Mac, so hosted CI runners cannot run them.

## Considered options

- One combined gate for the app, from unit and UI tests together. CI cannot run the UI tests, so the gate could not run there.
- A 90% gate for the app's unit tests. AppTests alone reach about 84%, so this would fail today.
- No gates. Coverage would slip with no warning.
- A 90% gate for FSearchKit and an 80% gate for the app's unit tests alone, with thin system adapters left out of the app number. This is the choice below.

## Decision

- CI fails if FSearchKit line coverage is below 90% (`scripts/coverage.sh --kit-only --min 90`).
- CI fails if app line coverage from AppTests alone is below 80% (`scripts/coverage.sh --unit-only --min 80`).
- The app number leaves out the thin system adapters listed in `scripts/coverage.sh` (the pass-throughs to `SMAppService`, `NSWorkspace`, `Process`, Trash, app activation and Sparkle). Tests replace these with fakes, as [ADR 0007](0007-test-seams-inert-test-host-and-test-mode.md) describes.
- The full app number, from the unit and UI tests together, comes from `make coverage` on a hands-off GUI session. It is not a CI gate.

## Consequences

- `make ci` runs both gates locally.
- A new system call needs a seam and a fake, or its lines count against the 80% floor.
- The app floor is lower than the FSearchKit floor on purpose. Raising it to 90% is on the maintainer to-do list.
- Adding a function to the exclusion list in `scripts/coverage.sh` is a reviewed decision. The script reports an excluded function that no longer exists.

See [Contributing](../../CONTRIBUTING.md).
