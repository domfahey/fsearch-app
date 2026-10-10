# To do

Ideas and follow-ups not done yet. Most important first within each section. "You" means the maintainer: these items need a decision, credentials or a public action.

## Now (small, closes a real gap)

- [ ] **App commands in the search panel:** typing "settings", "preferences" or "prefs" (a prefix match, so "set" works) shows an "FSearch Settings" row in its own section above the files; ↵ opens Settings. Matching is a pure FSearchKit function with tests; leave room for About and Quit rows later.
- [ ] **Launch at login for the app itself.** A Settings toggle (SMAppService.mainApp). Today only the helper starts at login, so the menu-bar icon and hotkey are missing after a reboot until the app is opened.
- [ ] **Uninstall from inside the app.** A Settings button, "Remove Background Helper and Data…": unregister the login item and move the data folder to the Trash. Document the Full Disk Access entry the user should remove by hand.
- [x] **Uninstall documentation.** A page covering the login item, the data folder (`~/Library/Application Support/FSearch`), the logs (`~/Library/Logs/FSearch`) and the Full Disk Access entry.
- [x] **Privacy manifest** (`PrivacyInfo.xcprivacy`): no tracking, no data collection, plus the required-reason APIs used (UserDefaults, file timestamps).
- [x] **PRIVACY.md:** what the index holds, that it stays on the Mac, no telemetry, Sparkle only checks for updates. Link it from the README and the About window.
- [ ] **Unified logging:** `os.Logger` with subsystem `com.domfahey.fsearch` and categories (daemon, panel, onboarding), so users can filter Console.app. No crash reporting service.
- [ ] **"Report an Issue…" menu item:** opens a new GitHub issue pre-filled with the app version, macOS version, chip and daemon status, for the user to review. Nothing is sent automatically.
- [x] **`LSApplicationCategoryType`** in Info.plist (`public.app-category.productivity`).
- [x] **Release script verification:** `xcrun stapler validate` and `codesign --verify --deep --strict` on the finished DMG; publish SHA-256 checksums.
- [x] **CI on the oldest supported macOS:** run the FSearchKit tests on the `macos-14` runner too. Today everything runs on macOS 26 with Apple silicon.
- [x] **Makefile:** `make lint`, `format`, `type`, `test`, `ui`, `coverage`, `bench`, matching the fsearch repo. CI calls the same targets.
- [x] **Lint in CI:** `swift format lint` with the repo's `.swift-format`, plus shellcheck and actionlint, and the `scripts/gen-credits.sh --check` drift check.
- [ ] **Coverage gate in CI:** fail below 90%, and post a report on each pull request.
- [x] **ROADMAP.md:**
  - the v2 search window;
  - clickable filter chips;
  - a possible Raycast extension;
  - the upstream daemon changes (version in `status`, agent ownership, query log).

## Found by benchmarks and cleanup

- [x] **PanelRows per keystroke** (FSearchKit done; SearchView must build `PanelRows` once per refresh to get the speedup): mapping 52 rows takes about 75 µs, because each `row(at:)` re-runs `hasFallbacks`/`QuerySplit.hasContentKey` on the query. Compute it once per query. `scripts/bench.sh` (`keystroke.panelRows.50`) proves the gain.
- [ ] **Leaked test daemon:** if `swift test` is killed (SIGKILL, CI timeout), RealDaemon's `fsearch serve` stays running under launchd with its temp HOME. Kill stale `/private/tmp/fsk-*` daemons at test start, and have the fixture's daemon exit when its parent dies (a watchdog pipe).
- [ ] **Re-record the benchmark baseline on a quiet machine:** the committed one is provisional (recorded under load). Run `scripts/bench.sh --record` after deleting this machine's entry in `bench/baseline.json`.
- [ ] **CI benchmark baseline:** add a `ci-macos-26` entry from a CI artifact so the CI bench job can gate, not just report.

## Code quality follow-ups (from reviews)

- [ ] **Formatting:** commit a `.swift-format` config (4-space indent, 140 columns) and apply it repo-wide (143 style-only issues today). Do it in one commit with no other changes.
- [ ] **Warnings as errors for our targets only:** set `SWIFT_TREAT_WARNINGS_AS_ERRORS` in project.yml for FSearch and the test targets. A command-line flag breaks KeyboardShortcuts, which builds with `-suppress-warnings`.
- [x] **Readable errors:** `DaemonError` has no `LocalizedError`, so the search log stores raw enum text (`daemon("bad regex")`), and one decode message says `tookUs` (a Swift name) instead of `took_us`. Tests label both as current-but-wrong.
- [x] **Reply ids:** DaemonClient never checks the `id` in replies; LineSocket would hand leftover buffered lines to the next request if the daemon ever sent two. Neither can happen with today's daemon, but checking ids makes it robust.
- [x] **Half-typed filters:** a content query like `foo size:` briefly sends an incomplete filter, and the daemon's error flashes under the field until the value is typed.
- [ ] **Small panel polish:**
  - the ⌘K menu opens at a fixed point instead of next to the selected row;
  - ⌘⌃Y also triggers Quick Look;
  - letter shortcuts don't match on non-Latin keyboard layouts;
  - Quick Look has no delegate, so no zoom animation and no arrow-key navigation.
- [ ] **API hygiene:** namespace FSearchKit's module-level free functions (`reduce`, `canContinue`, `openAtLine`, `installedEditors`, …), e.g. `PanelState.reduce`.
- [ ] **Review:** the privacy manifest's file-timestamp reason C617.1 is the closest fit for a non-sandboxed app; confirm before an App Store-style review matters.
- [x] **Verify:** dependabot.yml's `cooldown` field against GitHub's current schema (the first Dependabot run will reject it if unsupported).

## Upstream (fsearch) and the daemon pin

- [ ] Land the fsearch PR stack (#12 → #13 → #14; rebase #14 if PR #17 merges first), then move `scripts/build-daemon.sh` from the fork pin `d26cf78` to an upstream tag, and update THIRD_PARTY_NOTICES.md.
- [ ] Until then, keep the fork's `tests-daemon` branch (or tag the commit) so the pinned SHA stays reachable.
- [ ] Upstream daemon changes the app wants:
  - version in `status` (unlocks the "different fsearch running" banner);
  - agent ownership for the app's LaunchAgent;
  - the daemon-wide query log for debug mode's Search Log, with the client's pid (also unlocks the daemon pid in Index Details).
- [ ] Drop the `macos-14` CI leg before GitHub retires that image (fully unsupported Nov 2, 2026).

## GitHub settings (needs your go-ahead; repo-level changes)

- [ ] Turn on private vulnerability reporting (SECURITY.md already points to it).
- [ ] Turn on Dependabot alerts and security updates, and secret scanning with push protection.
- [ ] Protect `main`: require pull requests and green CI.
- [ ] Turn on GitHub Discussions and add SUPPORT.md (questions there, bugs in Issues).
- [ ] Labels: `good first issue`, `help wanted`, `upstream (fsearch)`.
- [ ] OpenSSF Scorecard workflow and badge.

## Before going public (you)

- [ ] Decide when to make github.com/domfahey/fsearch-app public (it's private now).
- [ ] Open a friendly issue on noahdunnagan/fsearch about the app, the name "FSearch for Mac", and the plan to offer it upstream.
- [ ] **App icon:** original, with light and dark variants. No Raycast or other third-party assets.
- [ ] Screenshots and a short demo GIF for the README (light and dark).
- [ ] **Gatekeeper and first-run documentation:** what a signed, notarized download looks like, why Full Disk Access is needed, and why the app isn't on the Mac App Store (it can't be sandboxed with Full Disk Access and a background helper).

## Releases (needs your Sparkle keys and Developer ID)

- [ ] The release checklist's user steps: the Task 0 Full Disk Access attribution experiment, Sparkle keys, the first real release run. See [docs/release-checklist.md](docs/release-checklist.md).
- [ ] Tag v0.1.0. Release notes come from CHANGELOG.md: one signed, notarized DMG with its SHA-256 checksum.
- [ ] GitHub artifact attestations (provenance) and an SBOM for each release.
- [ ] Sparkle appcast on GitHub Pages, with release notes in the update prompt (generated from the changelog). Keep delta updates and phased rollout as options for later.
- [ ] Homebrew cask, with a `zap` stanza that removes the login item, the data folder and the logs.
- [ ] **CONTRIBUTING:** explain that local builds are signed for that Mac only, and how a contributor can run their own build without the Developer ID.

## Platform polish

- [ ] **Accessibility:** VoiceOver labels on rows, chips and onboarding; full keyboard navigation in Settings and onboarding; respect Reduce Motion, Reduce Transparency and Increase Contrast.
- [ ] **Localization readiness:** move UI strings into a String Catalog (`Localizable.xcstrings`), English only for now.
- [ ] **Help menu:** README, keyboard shortcuts, query syntax, changelog.

## Later (features)

- [ ] **App Intents:** a "Search files" action for Shortcuts.
- [ ] **URL scheme:** `fsearch://search?q=…` opens the panel with a query.
- [x] **ARCHITECTURE.md:** a one-page map of the app, the daemon, the socket and the login item, for contributors.
- [ ] Stop duplicate CHANGELOG/About drift by generating more from one source if it grows.
