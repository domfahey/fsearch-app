# 0011. App unit-test coverage gate at 90%

Date: 2026-10-11
Status: Accepted. Supersedes the app gate in [ADR 0009](0009-coverage-gates.md).

## Context

[ADR 0009](0009-coverage-gates.md) set the app's unit-test gate at 80%, because AppTests alone reached about 84%. Most of the rest was SwiftUI view code. Tests could render a view but not read its text or press its buttons, so view tests could only check that nothing crashed.

SwiftUI builds its accessibility tree in the test host once the process has been asked an accessibility question. Tests can then read what a view shows and press its buttons, with no keystrokes, focus changes or visible windows. With view tests and a few small seams, AppTests alone reach about 92%.

## Considered options

- Keep the 80% gate. Coverage could slip by 10 points with no warning.
- Raise the gate to 90%, the same as FSearchKit. This is the choice below.
- Leave view code out of the app number. Views hold real behaviour, such as which buttons show and what they do, so they should count.

## Decision

- CI fails if app line coverage from AppTests alone is below 90% (`scripts/coverage.sh --unit-only --min 90`).
- The same system adapters as in ADR 0009 are left out of the number.
- View tests render off screen in the inert host and read or press views through their accessibility tree (`AppTests/Support/Accessibility.swift`). They never press a button that opens a real window or quits.

## Consequences

- `make ci` runs the 90% gate locally.
- A new view needs tests that read or press it, or its lines count against the floor.
- The view tests rely on SwiftUI building its accessibility tree in the test host. If a macOS release stops doing that, one test (`theAccessibilityTreeIsBuilt`) fails first and says so.

See [Contributing](../../CONTRIBUTING.md).
