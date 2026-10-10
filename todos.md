# To do

Ideas and follow-ups not done yet. Most important first within each section. "You" means the maintainer: these items need a decision, credentials or a public action.

## Now (small, closes a real gap)

- [ ] **Launch at login for the app itself.** A Settings toggle (SMAppService.mainApp). Today only the helper starts at login, so the menu-bar icon and hotkey are missing after a reboot until the app is opened.
- [ ] **Uninstall from inside the app.** A Settings button, "Remove Background Helper and Data…": unregister the login item and move the data folder to the Trash. Document the Full Disk Access entry the user should remove by hand.
- [ ] **Uninstall documentation.** A page covering the login item, the data folder (`~/Library/Application Support/FSearch`), the logs (`~/Library/Logs/FSearch`) and the Full Disk Access entry.
- [ ] **Privacy manifest** (`PrivacyInfo.xcprivacy`): no tracking, no data collection, plus the required-reason APIs used (UserDefaults, file timestamps).
- [ ] **PRIVACY.md:** what the index holds, that it stays on the Mac, no telemetry, Sparkle only checks for updates. Link it from the README and the About window.
- [ ] **Unified logging:** `os.Logger` with subsystem `com.domfahey.fsearch` and categories (daemon, panel, onboarding), so users can filter Console.app. No crash reporting service.
- [ ] **"Report an Issue…" menu item:** opens a new GitHub issue pre-filled with the app version, macOS version, chip and daemon status, for the user to review. Nothing is sent automatically.
- [ ] **`LSApplicationCategoryType`** in Info.plist (`public.app-category.productivity`).
- [ ] **Release script verification:** `xcrun stapler validate` and `codesign --verify --deep --strict` on the finished DMG; publish SHA-256 checksums.
- [ ] **CI on the oldest supported macOS:** run the FSearchKit tests on the `macos-14` runner too. Today everything runs on macOS 26 with Apple silicon.
- [ ] **Makefile:** `make lint`, `format`, `type`, `test`, `ui`, `coverage`, `bench`, matching the fsearch repo. CI calls the same targets.
- [ ] **Lint in CI:** `swift format lint` with the repo's `.swift-format`, plus shellcheck and actionlint, and the `scripts/gen-credits.sh --check` drift check.
- [ ] **Coverage gate in CI:** fail below 90%, and post a report on each pull request.
- [ ] **ROADMAP.md:**
  - the v2 search window;
  - clickable filter chips;
  - a possible Raycast extension;
  - the upstream daemon changes (version in `status`, agent ownership, query log).

## GitHub settings (needs your go-ahead; repo-level changes)

- [ ] Turn on private vulnerability reporting (SECURITY.md already points to it).
- [ ] Turn on Dependabot alerts and security updates, and secret scanning with push protection.
- [ ] Protect `main`: require pull requests and green CI.
- [ ] Turn on GitHub Discussions and add SUPPORT.md (questions there, bugs in Issues).
- [ ] Labels: `good first issue`, `help wanted`, `upstream (fsearch)`.
- [ ] OpenSSF Scorecard workflow and badge.

## Before going public (you)

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
- [ ] **ARCHITECTURE.md:** a one-page map of the app, the daemon, the socket and the login item, for contributors.
- [ ] Stop duplicate CHANGELOG/About drift by generating more from one source if it grows.
