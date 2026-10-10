# To do

Follow-ups not done yet, grouped by priority. "You" items need the maintainer: a decision, credentials, design work or a public action. Done items are kept at the bottom for the record until the next release.

## P1: next batch (app code; starts when the app-coverage work merges)

- [x] **App commands in the search panel:** typing "settings", "preferences" or "prefs" (prefix match, so "set" works) shows an "FSearch Settings" row in its own section above the files; ↵ opens Settings. Matching is a pure FSearchKit function with tests; leave room for About and Quit rows later.
- [x] **Launch at login for the app itself:** a Settings toggle (SMAppService.mainApp). Today only the helper starts at login, so the menu-bar icon and hotkey are missing after a reboot until the app is opened.
- [x] **Uninstall from inside the app:** a Settings button, "Remove Background Helper and Data…", that unregisters the login item and moves the data folder to the Trash. Update docs/uninstall.md to point to it.
- [x] **Full Disk Access reminder after Skip:** the spec promises a gentle menu-bar reminder when onboarding's Full Disk Access step is skipped. Today `MenuBarWarning.evaluate` stays silent after a skip. Show a dismissable reminder and update docs/reference/troubleshooting.md.
- [x] **Unified logging:** `os.Logger` with subsystem `com.domfahey.fsearch` and categories (daemon, panel, onboarding), so users can filter Console.app. No crash reporting service.
- [x] **"Report an Issue…" menu item:** opens a new GitHub issue pre-filled with the app version, macOS version, chip and daemon status, for the user to review. Nothing is sent automatically.
- [x] **Use the faster PanelRows in the panel:** FSearchKit now builds `PanelRows(files:query:mode:)` once per query (about 103 µs down to 1.8 µs for 50 rows); SearchView still calls the old static functions per row. Build it once per refresh.
- [ ] **Coverage gate in CI:** fail below 90% (FSearchKit and app), and post a report on each pull request. Uses the app-coverage script.
- [ ] **Warnings as errors for our targets only:** set `SWIFT_TREAT_WARNINGS_AS_ERRORS` in project.yml for FSearch and the test targets (a command-line flag breaks KeyboardShortcuts). The two UI-test concurrency warnings must be gone first.
- [x] **Apply formatting:** run `make format` repo-wide in one commit with no other changes (259 style-only issues), then remove `continue-on-error` from the CI swift-format step.
- [x] **docs/architecture.md:** describes AppTests, the seams, the UI tests and coverage.
- [x] **Help menu:** README, docs index, keyboard shortcuts, query syntax, changelog.

## P1: repository layout

- [x] **Tidy the root folder:** community files (CODE_OF_CONDUCT, SECURITY, SUPPORT) live in `.github/`; architecture, privacy, roadmap and this file live in `docs/`. README, LICENSE, CHANGELOG, CONTRIBUTING and THIRD_PARTY_NOTICES stay at the root. Every link was updated and checked with scripts/check-links.sh.

## P1: Sparkle (from Sparkle's setup guide)

- [x] **Gentle update reminders:** FSearch is a menu-bar (`LSUIElement`) app, so scheduled update alerts can open behind other windows. Implement `SPUStandardUserDriverDelegate.supportsGentleScheduledUpdateReminders`: a quiet menu-bar indicator plus an "Update Available…" menu item.
- [x] **Signed feeds:** set `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` to YES (Sparkle 2.9+; we pin 2.10). DMG updates keep EdDSA key rotation possible.
- [x] **Incrementing `CFBundleVersion`:** it's hard-coded to `1`. `release.sh` sets it from `git rev-list --count HEAD` and refuses to go backwards; `CFBundleShortVersionString` comes from the tag.
- [x] **Update settings:** "Automatically check for updates" (bound to `SPUUpdater.automaticallyChecksForUpdates`) and "Check Now" in Settings, shown only when the updater is configured.
- [x] **No system profiling:** set `SUEnableSystemProfiling` to NO explicitly in Info.plist, matching docs/privacy.md.
- [x] **Strip Sparkle's XPC services** (not needed when not sandboxed) at build time, so there's less to sign and notarize. Update `release.sh` to match.
- [ ] **Archive and export with Developer ID:** replace the ad-hoc archive plus manual nested signing with `xcodebuild archive` + `-exportArchive` (an `ExportOptions.plist` with method `developer-id`). Keep the staple, codesign and spctl checks.
- [ ] **Automate the appcast:** `release.sh` keeps a folder with every released DMG (for deltas), writes `<dmg>.md` release notes from the CHANGELOG section, and runs `generate_appcast` from the SwiftPM artifacts (`…/artifacts/sparkle/Sparkle/bin/`). Run locally only; the EdDSA private key never goes to CI or the web host.
- [ ] **You:** back up the EdDSA private key with `generate_keys -x <file>` somewhere safe. Test the first update by lowering `CFBundleVersion` and running `defaults delete com.domfahey.fsearch SULastCheckTime`. Keep the dSYMs.

## P1: test safety

- [x] **App tests must never take focus:** some AppTests made the real launcher panel the key window, stealing keystrokes (fixed for the panel). Onboarding, Quick Look, the activate call, the UI-test guard, throwaway defaults for UI tests, and clipboard restore are in progress, along with the low-signal app tests. Until done: no AppTests or UI test runs while someone is using the Mac.

## P1: tests and benchmarks

- [ ] **Re-record the benchmark baseline on a quiet machine:** the committed one is provisional (recorded under load). Delete this machine's entry in `bench/baseline.json`, then `scripts/bench.sh --record`.
- [ ] **CI benchmark baseline:** add a `ci-macos-26` entry from a CI artifact so the CI bench job can gate, not just report.

## P2: code quality and polish

- [ ] **AppTests cleanup at end of run:** throwaway `com.domfahey.fsearch.apptests.*` plists are swept at the start of the next run but about 24 remain after each run; remove them in teardown too.
- [ ] **UI-test builds register the global ⌥Space hotkey** while running; skip hotkey registration in test mode.
- [ ] **Test-only API in shipped code:** wrap `OnboardingLauncher.reset()` and the `private(set)` widenings added for AppTests in `#if DEBUG`.
- [ ] **One source for launch options:** `PanelController` reads `LaunchOptions.current.showPanel`; use `app.options` like everything else.
- [x] **Docs best-practice pass:** README points to the docs index; troubleshooting shows the new error texts; query syntax explains that half-typed filters wait; ARCHITECTURE mentions reply ids; a Markdown link check in CI.
- [ ] **Small panel polish:**
  - the ⌘K menu opens at a fixed point instead of next to the selected row;
  - ⌘⌃Y also triggers Quick Look;
  - letter shortcuts don't match on non-Latin keyboard layouts;
  - Quick Look has no delegate, so no zoom animation and no arrow-key navigation.
- [ ] **API hygiene:** namespace FSearchKit's module-level free functions (`reduce`, `canContinue`, `openAtLine`, `installedEditors`, …), e.g. `PanelState.reduce`.
- [ ] **Accessibility:** VoiceOver labels on rows, chips and onboarding; full keyboard navigation in Settings and onboarding; respect Reduce Motion, Reduce Transparency and Increase Contrast.
- [ ] **Localization readiness:** move UI strings into a String Catalog (`Localizable.xcstrings`), English only for now.
- [ ] **Query docs depth:** docs/reference/query-syntax.md doesn't yet describe ranking, typo tolerance, how several plain words combine, or how `limit:` interacts with the app's 50-result request. Fill these in after checking them against the daemon.
- [ ] **Verify by hand, then fix the docs if needed:** ⌥⌘D works while the menu is closed; `defaults delete com.domfahey.fsearch` clears the app's settings.
- [ ] Generate more of CHANGELOG/About from one source if they start to drift.

## P2: later features

- [ ] **Everything-style search window (v2):** a full window with a sortable results table (name, folder, size, kind, date modified), a status bar, match-case/regex/path toggles, filter chips, saved searches and a preview pane. See docs/roadmap.md. Needs a design pass, and daemon paging for large result sets.
- [ ] **App Intents:** a "Search files" action for Shortcuts.
- [ ] **URL scheme:** `fsearch://search?q=…` opens the panel with a query.

## Upstream (fsearch) and the daemon pin

- [ ] Land the fsearch PR stack (#12 → #13 → #14; rebase #14 if PR #17 merges first), then move `scripts/build-daemon.sh` from the fork pin `d26cf78` to an upstream tag, and update THIRD_PARTY_NOTICES.md.
- [ ] Until then, keep the fork's `tests-daemon` branch (or tag the commit) so the pinned SHA stays reachable.
- [ ] Upstream daemon changes the app wants:
  - version in `status` (unlocks the "different fsearch running" banner);
  - agent ownership for the app's LaunchAgent;
  - the daemon-wide query log for debug mode's Search Log, with the client's pid (also unlocks the daemon pid in Index Details).
- [ ] Drop the `macos-14` CI leg before GitHub retires that image (fully unsupported Nov 2, 2026).

## You: GitHub settings (repo-level changes; needs your go-ahead)

- [x] Turn on private vulnerability reporting (.github/SECURITY.md already points to it).
- [x] Turn on Dependabot alerts and security updates, and secret scanning with push protection.
- [x] Protect `main`: pull requests and green CI (lint, app, kit on macOS 14 and 26) required; admins can still push in an emergency.
- [x] Turn on GitHub Discussions (.github/SUPPORT.md already points to it).
- [x] Labels: `question`, `good first issue`, `help wanted`, `upstream (fsearch)`.
- [x] OpenSSF Scorecard workflow and badge (runs on push to main and weekly).

## You: before announcing

- [ ] **App icon:** original, with light and dark variants. No Raycast or other third-party assets.
- [ ] Screenshots and a short demo GIF for the README (light and dark).

## You: releases (needs your Sparkle keys and Developer ID)

- [ ] The release checklist's user steps: the Task 0 Full Disk Access attribution experiment (the docs say which binary to look for once it's settled), Sparkle keys, the first real release run. See [docs/release-checklist.md](release-checklist.md).
- [ ] Check the Zed, Sublime Text and BBEdit open-at-line commands on a Mac that has them.
- [ ] Tag v0.1.0. Release notes come from CHANGELOG.md: one signed, notarized DMG with its SHA-256 checksum. Switch the changelog's `[Unreleased]` link to a compare link.
- [ ] GitHub artifact attestations (provenance) and an SBOM for each release.
- [ ] Sparkle appcast on GitHub Pages, with release notes in the update prompt (generated from the changelog). Delta updates and phased rollout are options for later.
- [ ] Homebrew cask, with a `zap` stanza that removes the login item, the data folder and the logs.
- [ ] Confirm the privacy manifest's file-timestamp reason (C617.1), the closest fit for a non-sandboxed app.

## Done

- [x] Told the fsearch maintainer: https://github.com/noahdunnagan/fsearch/issues/18 (name, upstream, three daemon changes). Follow up on the reply.
- [x] Unreleased work pushed to `main`: the public page credits fsearch and has the docs.
- [x] Leaked test daemon: a watchdog pipe kills it when the test process dies, and orphans are swept at start.
- [x] Repo made public, with a description crediting fsearch and its inspirations, and topics.
- [x] Docs following Diátaxis: index, first-search tutorial, how-to guides, reference (shortcuts, query syntax, settings, files, troubleshooting, FAQ) and ADRs 0001–0006.
- [x] docs/privacy.md (fsearch itself has no network code), .github/SUPPORT.md, docs/roadmap.md, docs/install.md (Gatekeeper, first run, why not the App Store), docs/uninstall.md.
- [x] docs/architecture.md and CONTRIBUTING's "Running your own build" (local builds are signed for that Mac only).
- [x] Privacy manifest (`PrivacyInfo.xcprivacy`) and app category (Productivity).
- [x] Release script verification (staple, signature, SHA-256 checksum).
- [x] CI on macOS 14 (Xcode 16.2) and macOS 26.
- [x] Makefile, `.swift-format` config, and CI lint job (credits drift, scripts, workflows, swift-format report-only).
- [x] Readable daemon errors and reply id checks.
- [x] PanelRows built once per query in FSearchKit; half-typed filters wait for their value.
- [x] Changelog audited against git history (twice; latest covers readable errors, reply ids, half-typed filters and the docs).
- [x] Dependabot `cooldown` checked against GitHub's options reference.
