# 0012. Coverage gates at 95%

Date: 2026-11-25
Status: Accepted. Supersedes [ADR 0009](0009-coverage-gates.md) and [ADR 0011](0011-app-unit-test-gate-at-90.md).

## Context

[ADR 0009](0009-coverage-gates.md) set the FSearchKit floor at 90%, and [ADR 0011](0011-app-unit-test-gate-at-90.md) raised the app unit-test floor to 90% once SwiftUI accessibility-tree view tests brought AppTests to ~92%.

With small seams on startup guards, `PanelController`, `Updater`, `SearchLogView`, `SettingsView`, `Uninstaller`, `QuickLookSource`, and `LineSocket`, plus tests exercising every view action button and error path in the inert host, FSearchKit reaches ~98.8% and AppTests alone reach ~97.5% excluding system adapters (~96.8% raw), with every non-adapter source file above 95%.

## Considered options

- Keep both gates at 90%. App coverage could drop by more than 7 points and FSearchKit by nearly 9 points before CI notices.
- Raise both gates to 95%. Leaves a 2.5–3.8 point buffer above the gate while catching regressions in new views, lifecycle glue, or transport error paths. This is the choice below.
- Gate every individual file at 95%. A small refactor in a short file can move it by several points without losing meaningful test coverage.

## Decision

- CI fails if FSearchKit line coverage is below 95% (`scripts/coverage.sh --kit-only --min 95`).
- CI fails if app line coverage from AppTests alone (excluding the documented system adapters in `scripts/coverage.sh`) is below 95% (`scripts/coverage.sh --unit-only --min 95`).
- The exclusion list in `scripts/coverage.sh` stays unchanged: only thin pass-throughs to `SMAppService`, `NSWorkspace`/Trash, `NSApp.activate`, and Sparkle are excluded.

## Consequences

- `make ci` runs both 95% gates locally.
- New app glue, views, or transport error handling need seams and tests in the inert host or they will pull coverage toward the floor.

See [Contributing](../../CONTRIBUTING.md).
