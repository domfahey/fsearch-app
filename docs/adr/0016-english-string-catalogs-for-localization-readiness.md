# 0016. English String Catalogs for localization readiness

Date: 2026-11-24
Status: Accepted

## Context

All user-facing text was written as literals in code. Adding a language later would mean finding and rewriting every string. The text lives in two places: the app (`App/`) and the `FSearchKit` package, which builds menu, onboarding and error messages.

## Considered options

- Leave literals in place and localize when a translation is requested. Cheap now, but a large, risky sweep later.
- Ship English String Catalogs now, with no other languages yet. This is the choice below.
- Use legacy `.strings` files. String Catalogs are Xcode's current format and are filled from compiler output.

## Decision

Keep one English String Catalog per module: `App/Resources/Localizable.xcstrings` and `Packages/FSearchKit/Sources/FSearchKit/Resources/Localizable.xcstrings`.

- `project.yml` sets the development language to `en` and turns on string-catalog extraction. `Package.swift` sets `defaultLocalization: "en"` and processes `Resources`.
- User-facing text goes through `LocalizedStringKey`, `Text`, or `String(localized:)`. In FSearchKit, that is `String(localized:bundle: .module)`.
- Technical tokens (UI-test state markers, keycaps, syntax examples) use `Text(verbatim:)` or `shouldTranslate: false`, so they are not offered to translators. Ids such as `PanelMenuItem.id` do not depend on the locale.
- `scripts/sync-strings.sh` (`make strings`) refreshes both catalogs from the compiler's `.stringsdata`, drops stale keys and marks English entries as translated.
- `LocalizationTests` in `AppTests` and in FSearchKit check the development region, the compiled `en` strings and English lookups.

## Consequences

- Adding a language means translating the catalogs, not editing code.
- New user-facing strings must be wrapped, and `make strings` run, or the catalog drifts.
- No translations ship yet. English is the only language the tests cover.
