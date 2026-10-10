# To do

Open work, by priority. "You" items need the maintainer: a decision, credentials, design work or a public action. Finished work lives in [CHANGELOG.md](../CHANGELOG.md) and the git history, not here.

Detail for the bug-audit items is in `.superpowers/audit-round2.md`, and for the final-review fixes in `.superpowers/final-fix-brief.md`. Both are local working notes, not committed.

## In flight

- [ ] **Makefile audit:** stricter shell, phony targets, `clean`, plus new `doctor`, `install` (developer prerequisites only), `setup` and `ci` targets. *(in progress)*
- [ ] **Security best-practices audits** (app/platform, supply chain/CI/repo): triage the findings. *(results pending)*
- [ ] **Docs and developer-docs audits:** apply the findings. *(results pending)*

## P1: bugs from audit round 2

- [ ] **The panel opens partly off-screen** on displays shorter than about 1290pt (the built-in 1512×982 included). Clamp `y` in `PanelController`.
- [ ] **Stale ↵:** while new results load, ↵ opens the previous query's hit. Tag results with the (query, mode) they answer, and hold actions until they match.
- [ ] **The list doesn't scroll to the keyboard selection** past about row 10. Use `ScrollViewReader`.
- [ ] **After an app update the old helper keeps running.** Store the helper's identity; at launch, if it changed and we own the daemon, restart once.
- [ ] **A Full Disk Access grant made after onboarding never takes effect.** After "Turn On Full Disk Access…", restart the helper on the next activation, as onboarding does.
- [ ] **A leftover CLI LaunchAgent plist with no running daemon** blocks our helper, and onboarding sticks at step 2. Recheck, then register; never take over a *running* CLI daemon.
- [ ] **`ownsDaemon` trusts the login item, not the process serving the socket.** Decide from the socket holder: the pid in `socket.lock` and its path.
- [ ] **Disconnect restarts aren't serialized.** Keep one in-flight restart.
- [ ] **Content search for `kind: Deployment` or `size: 3`** is read as an empty filter. In content and symbols modes, only `key:value` counts as a filter.
- [ ] **`limit:` is ignored in name searches**, because the app always sends JSON `limit: 50`. Leave out the JSON limit when the query has one.
- [ ] **Accented names (NFD on disk, NFC typed) aren't found.** App-side mitigation: also send the NFD form and merge the results. The real fix is upstream.
- [ ] **The socket accepts any same-user process.** Document this in docs/privacy.md, .github/SECURITY.md and docs/architecture.md (upstream fix below).

## P2: smaller bugs and polish

- [ ] Panel: key repeat for ↑/↓/⌃N/⌃P; missing files shouldn't open silently or land in Recents; Open With errors are dropped; Terminal on a package opens inside the bundle; dotted folder names get a document icon; ⌘Y and other letter shortcuts on non-Latin layouts; the ⌘K menu opens at a fixed point; ⌘⌃Y also triggers Quick Look; Quick Look has no arrow-key navigation.
- [ ] Lifecycle: the helper writes no daemon.log; Settings and debug windows open behind other apps; the update reminder is lost on relaunch; status decoding is too strict for older CLI daemons (decode new fields optionally); no single-instance guard.
- [ ] Search: a half-typed filter freezes stale results after paste or a mode change; partly typed filter values (`type:c`, `size:1mb..`) flash errors; a timeout or a spent restart budget shows "Starting search…" forever; Recents checks files on the main thread.
- [ ] Indexing poll loops while the panel is hidden.
- [ ] Build: `cargo build --locked`, and build the daemon before the CI release job unlocks the signing keychain.
- [ ] Test-only API in shipped code: wrap it in `#if DEBUG`.
- [ ] One source for launch options: `PanelController` still reads `LaunchOptions.current.showPanel`; use `app.options`.
- [ ] One empty `com.domfahey.fsearch.apptests.unit.plist` stays in ~/Library/Preferences after a full AppTests run (cfprefsd writes it back); it is swept on the next run.
- [ ] API hygiene: namespace FSearchKit's free functions (`reduce`, `canContinue`, `openAtLine`, …).
- [ ] Raise the CI app unit-test coverage gate from 80% to 90% (the FSearchKit gate is already 90%).
- [ ] CI benchmark baseline: add a `ci-macos-26` entry from a CI artifact, so the bench job can gate.
- [ ] Accessibility: VoiceOver labels, keyboard navigation in Settings and onboarding, Reduce Motion and Transparency, Increase Contrast.
- [ ] Localization readiness: a String Catalog, English only for now.
- [ ] Query docs depth: ranking, typo tolerance, how words combine, `limit:`. Check each against the daemon first.

## P2: features

- [ ] Everything-style search window (v2): sortable table, status bar, match toggles, filter chips, saved searches, preview pane. Needs a design pass and daemon paging. See [roadmap](roadmap.md).
- [ ] App Intents: a "Search files" action for Shortcuts.
- [ ] URL scheme: `fsearch://search?q=…`.
- [ ] Sparkle: archive and export with Developer ID (`xcodebuild -exportArchive`), and script `generate_appcast` (with deltas and release notes from the CHANGELOG) as a local release step.

## Upstream (fsearch)

- [ ] Land the PR stack #12 → #13 → #14 (rebase #14 if #17 merges first). Then move `scripts/build-daemon.sh` from the fork pin `d26cf78` to an upstream tag and update THIRD_PARTY_NOTICES.md. Until then, keep the fork's `tests-daemon` branch.
- [ ] Daemon changes the app wants:
  - version in `status`;
  - agent ownership for the app's LaunchAgent;
  - a daemon-wide query log;
  - **check the connecting client's code signature** on the socket;
  - Unicode normalization and case folding for names and queries;
  - apply the query's `limit:` over the JSON limit;
  - a daemon.log path option for the bundled helper.
- [ ] Decide whether macOS 14 stays the minimum. Then drop the `macos-14` CI leg before GitHub retires that image (Nov 2, 2026), or move it to `macos-15`.

## You

**Signing and releases**
- [x] Developer ID Application certificate: `Developer ID Application: Dominic Fahey (MR3WJZ83MR)`.
- [ ] Back up that certificate as a `.p12` (Keychain Access → Export). CI's signing secret needs it too.
- [ ] `xcrun notarytool store-credentials fsearch-notary --apple-id … --team-id MR3WJZ83MR`. For CI, also create an App Store Connect API key.
- [ ] Sparkle: run `generate_keys`, back up the private key with `generate_keys -x`, and send the public key, which goes into `SUPublicEDKey`.
- [ ] Task 0: the Full Disk Access attribution experiment (which binary macOS lists).
- [ ] Set up the GitHub Pages site behind `SUFeedURL`, and add the CI secrets listed in docs/release-checklist.md.
- [ ] Test an update: install a build with a lowered `CFBundleVersion`, run `defaults delete com.domfahey.fsearch SULastCheckTime`, and confirm the update is offered.
- [ ] Tag v0.1.0 and run `scripts/release.sh 0.1.0`; GitHub release with DMG + SHA-256; artifact attestations and SBOM; Homebrew cask (with `zap`).
- [ ] Confirm the privacy manifest's file-timestamp reason (C617.1).

**On an idle Mac** (these tests synthesize keystrokes)
- [ ] Run the 16 end-to-end UI tests (`make ui`).
- [ ] Re-record the benchmark baseline (`scripts/bench.sh --record`, after deleting this machine's entry).
- [ ] Manual checks:
  - the ⌥Space hotkey and the Raycast warning;
  - Zed, Sublime Text and BBEdit open-at-line;
  - Japanese and Chinese input in the panel;
  - ⌥⌘D with the menu closed;
  - `defaults delete com.domfahey.fsearch` clears settings.

**Design and outreach**
- [ ] App icon (original; no third-party assets) and README screenshots or a demo GIF.
- [ ] Follow up on noahdunnagan/fsearch#18.
