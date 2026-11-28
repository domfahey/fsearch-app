# Coding Agent Guardrails

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/architecture.md](docs/architecture.md) for full context. Key invariants for automated agents:

## Repository Layout & Architecture Boundary

- **`Packages/FSearchKit/`** — Pure Swift 6 library (zero external dependencies) containing query splitting/compiling, wire protocol, daemon client, search models, launchable rules, recents, saved searches, and search logging. Put new testable logic here first.
- **`App/`** — Thin SwiftUI + AppKit shell (Classic floating panel, Everything-style Search Window, Menu Bar, Settings, Onboarding, App Intents).
- **OS Seams** — Side effects (`SMAppService`, `NSWorkspace`, `FileManager.trashItem`, `NSApp.activate`, Sparkle) sit behind protocols in `App/Support/Seams.swift` with thin pass-throughs in `App/Support/SystemSeams.swift`.
- See [docs/architecture.md](docs/architecture.md), [CONTRIBUTING.md](CONTRIBUTING.md), and [docs/adr/README.md](docs/adr/README.md).

## Safety & Focus Guardrails (Non-Negotiable)

- **Never run `make ui` (`scripts/ui-smoke.sh`) unsupervised.** It launches real app windows and synthesizes real keyboard events. Only run UI tests when the user explicitly provides an idle GUI session.
- **Unit tests must stay inert** (ADR 0005, ADR 0007): never touch `~/Library/Application Support/FSearch`, `~/Library/LaunchAgents`, `~/Library/Preferences/com.domfahey.fsearch.plist`, `~/Library/Logs/FSearch`, Keychain, or the user's real pasteboard. Always use `TestEnv` (`AppTests/Support/Fakes.swift`), `Presentation.inert`, `HostSafeWindow`, and the `FileActions.workspace` / `FileActions.pasteboard` seams.
- **Never stop or replace a CLI daemon** (ADR 0003, ADR 0017): destructive daemon lifecycle operations require positive ownership (`ownsDaemon` / `dataOwnership == .ours`).
- **Never spawn editors or tools as child processes** (ADR 0018): child processes inherit FSearch's Full Disk Access. Always launch via LaunchServices (`NSWorkspace`) after verifying `Editor.codeRequirement`.

## Build, XcodeGen & Pinned Dependencies

- `FSearch.xcodeproj` is generated from `project.yml` via `make project` (`scripts/generate-project.sh`). Never hand-edit `FSearch.xcodeproj/project.pbxproj`; edit `project.yml` and regenerate.
- Keep `Package.resolved` untouched unless explicitly updating `KeyboardShortcuts` or `Sparkle` (CI passes `-onlyUsePackageVersionsFromResolvedFile`).
- Swift 6 strict concurrency and warnings-as-errors apply everywhere: `make type` rejects any warning in `App/`, `AppTests/`, `AppUITests/`, or `Packages/`.

## Localization (String Catalogs)

- When adding or editing any user-facing localized string in `App/` or `Packages/FSearchKit/`, run `make strings` (`scripts/sync-strings.sh`) and populate translations for **all 8 locales** (`de`, `en`, `es`, `fr`, `ja`, `ko`, `pt-BR`, `zh-Hans`) in `App/Resources/Localizable.xcstrings` and `Packages/FSearchKit/Sources/FSearchKit/Resources/Localizable.xcstrings`. `scripts/check-strings.sh` enforces 8-locale completeness (and rejects stale keys) inside `make lint`.

## Coverage Gates (ADR 0012)

- CI enforces **95% line coverage** on both `FSearchKit` (`scripts/coverage.sh --kit-only --min 95`) and `FSearch.app` excluding system adapters (`scripts/coverage.sh --unit-only --min 95`).
- `scripts/coverage.sh` lists excluded system-adapter functions by exact `xccov` symbol name in `EXCLUDE`. If you rename or remove an excluded function in `App/Support/SystemSeams.swift`, `App/Updates/Updater.swift`, or `App/Support/Seams.swift`, update `EXCLUDE` in the same commit or coverage will fail.

## Git Workflow & Hooks

- Never pass `git commit --no-verify` (`scripts/hooks/` runs secret checks; fix false positives in `scripts/hooks/check-secrets.sh`).
- Commit messages use an imperative subject with an optional capitalized prefix (`Feat:`, `Fix:`, `Security:`, `Panel:`, `Window:`, `Docs:`, `Tests:`, `CI:`, `Chore:`).

## Verification Commands

| Purpose | Command |
|---|---|
| Targeted FSearchKit tests | `cd Packages/FSearchKit && swift test --filter <SuiteOrTest>` |
| All FSearchKit tests | `make test` |
| Targeted AppTests suite | `xcodebuild test -project FSearch.xcodeproj -scheme FSearch -derivedDataPath build -only-testing:AppTests/AppTests/<SuiteName> CODE_SIGNING_ALLOWED=NO` |
| Format Swift sources in place | `make format` |
| Lint (swift-format, links, strings, credits, appcast, shellcheck, actionlint) | `make lint` |
| Warnings-as-errors typecheck | `make type` |
| Coverage gates (95%) | `scripts/coverage.sh --kit-only --min 95` and `scripts/coverage.sh --unit-only --min 95` |
| Full CI equivalent | `make ci` |
