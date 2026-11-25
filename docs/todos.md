# To do

Open work, by priority. "You" items need the maintainer: a decision, credentials, design work or a public action. Finished work lives in [CHANGELOG.md](../CHANGELOG.md) and the git history, not here.

## P2: smaller bugs and polish

- [ ] One empty `com.domfahey.fsearch.apptests.unit.plist` stays in ~/Library/Preferences after a full AppTests run (cfprefsd writes it back); it is swept on the next run.

## Docs follow-ups

- [ ] Switch the Help menu links (`HelpLinks.base`, `blob/main`) to tag-pinned links after 0.1.0.
- [ ] Confirm the GitHub Pages location for the appcast (the runbook assumes a `gh-pages` branch with `appcast.xml` at its root).
- [ ] Check external drives (`/Volumes`); the docs currently say "untested, probably not indexed".

## P2: features

- [ ] Everything-style search window (v2): sortable table, status bar, match toggles, filter chips, saved searches, preview pane. Needs a design pass and daemon paging. See [roadmap](roadmap.md).
- [ ] Non-English translations (English String Catalogs for the app and FSearchKit are already in place).

## Upstream (fsearch)

- [ ] Land the PR stack #12 → #13 → #14 (rebase #14 if #17 merges first). Then move `scripts/build-daemon.sh` from the fork pin `d26cf78` (tagged `app-pin-2026-10-10`) to an upstream tag and update THIRD_PARTY_NOTICES.md. Until then, keep the fork's `tests-daemon` branch.
- [ ] Daemon changes the app wants (the socket peer check is a security issue: report it privately, through a security advisory on noahdunnagan/fsearch, not a public issue):
  - version in `status`;
  - agent ownership for the app's LaunchAgent;
  - a daemon-wide query log;
  - **check the connecting client's code signature** on the socket;
    once the daemon checks peers, Debug and ad-hoc builds of this app will be refused; give developers a path (an `allowed-clients` entry written by `make daemon`, or the opt-out in test mode) and document it in CONTRIBUTING;
  - Unicode normalization and case folding for names and queries;
  - apply the query's `limit:` over the JSON limit;
  - a daemon.log path option for the bundled helper: let the daemon open its own `daemon.log` via a flag or env var (SMAppService plists can't set a per-user `StandardErrorPath`).

## You

**Signing and releases**
- [ ] Back up the `Developer ID Application: Dominic Fahey (MR3WJZ83MR)` certificate as a `.p12` (Keychain Access → Export). CI's signing secret needs it too.
- [ ] `xcrun notarytool store-credentials fsearch-notary --apple-id … --team-id MR3WJZ83MR`. For CI, also create an App Store Connect API key.
- [ ] Sparkle: run `generate_keys`, back up the private key with `generate_keys -x`, and put the public key into `SUPublicEDKey`.
- [ ] Task 0: the Full Disk Access attribution experiment (which binary macOS lists).
- [ ] Set up the GitHub Pages site behind `SUFeedURL`, and add the CI secrets listed in docs/release-checklist.md.
- [ ] Test an update: install a build with a lowered `CFBundleVersion`, run `defaults delete com.domfahey.fsearch SULastCheckTime`, and confirm the update is offered.
- [ ] Tag `v0.1.0` on `main` (CI's `release` job builds the DMG, `.sha256` and `.intoto.jsonl` provenance attestation into a draft GitHub release; local fallback: `scripts/release.sh 0.1.0`), run `scripts/appcast.sh`, publish the release and `gh-pages` appcast, then add a Homebrew cask (with `zap`).

**By hand**
- [ ] Manual checks:
  - the ⌥Space hotkey and the Raycast warning;
  - Japanese and Chinese input in the panel;
  - ⌥⌘D with the menu closed;
  - `defaults delete com.domfahey.fsearch` clears settings;
  - the panel frame on the built-in display, held ↵ replay, scrolling to the selection;
  - editor URL schemes for VS Code and Cursor (and Zed, Sublime Text and BBEdit if installed).

**Design and outreach**
- [ ] Review the app's new launch-time "Move to Applications" alert wording.
- [ ] App icon (original; no third-party assets) and README screenshots or a demo GIF.
- [ ] Follow up on noahdunnagan/fsearch#18.
