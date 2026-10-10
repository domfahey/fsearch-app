# Release runbook

This runbook is for maintainers cutting a release of FSearch for Mac. Nothing has been released yet. Version 0.1.0 is next.

Follow the sections in order. Do the setup once, then repeat "Cut a release" for each version.

## Set up once

- [ ] Generate the Sparkle EdDSA key pair with Sparkle's `generate_keys` (in `build/SourcePackages/artifacts/sparkle/Sparkle/bin/` after a build). The private key goes in your Keychain. Put the printed public key in `SUPublicEDKey` in `App/Resources/Info.plist`. Until you do, the key reads `REPLACE_WITH_SPARKLE_PUBLIC_KEY`, the updater does not start, **Check for Updates…** is hidden and `scripts/release.sh` refuses to run.
- [ ] Back up the private key: `generate_keys -x fsearch-sparkle-private.key` exports it from the Keychain. Keep the file in a password manager, never in the repo. If you lose it, existing installs cannot update. Restore it on another Mac with `generate_keys -f fsearch-sparkle-private.key`.
- [ ] Install a Developer ID Application certificate, then `export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"`.
- [ ] Store notary credentials: `xcrun notarytool store-credentials fsearch-notary`.
- [ ] Set up the GitHub Pages site behind `SUFeedURL` (`https://domfahey.github.io/fsearch-app/appcast.xml`). Serve it from the root of a `gh-pages` branch, so `appcast.xml` sits at the top level.
- [ ] For tag builds in CI, add these repository secrets: `DEVELOPER_ID`, `DEVELOPER_ID_CERT_P12_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`, `KEYCHAIN_PASSWORD`, `NOTARY_API_KEY_P8_BASE64` (the `.p8` file, base64), `NOTARY_API_KEY_ID` and `NOTARY_API_ISSUER_ID`.

## Cut a release

### 1. Prepare the version

- [ ] Make sure `main` is green in CI and that `make ci` passes locally.
- [ ] Update `MARKETING_VERSION` in `project.yml` to the new version. Release builds take their version from the tag, but Debug builds show this value.
- [ ] In [CHANGELOG.md](../CHANGELOG.md), rename the Unreleased section to `## [X.Y.Z] - YYYY-MM-DD`. Add a new empty `## [Unreleased]` above it. Update the compare links at the bottom: `[Unreleased]` compares `vX.Y.Z...main`, and `[X.Y.Z]` compares the previous tag to `vX.Y.Z` (for the first release, link to the tag itself).
- [ ] Commit these changes on `main`.
- [ ] Check the build number. `scripts/release.sh` sets `CFBundleShortVersionString` from the version and `CFBundleVersion` from `git rev-list --count HEAD`, so it needs a full clone. The number must be greater than the `sparkle:version` of the last appcast entry, or Sparkle will not offer the update. Tag releases only on commits of `main`, whose commit count only grows. The script refuses a build number that is not greater than the last release's: the highest `git rev-list --count` among the other `v*` tags, and `release/last-build` if that file exists. CI's checkout fetches the full history and the tags for this, and the job fails if it finds no `v*` tag.

### 2. Tag

- [ ] Create the tag. Sign it if you have signing configured: `git tag -s vX.Y.Z -m "FSearch X.Y.Z"`. Otherwise use `git tag -a vX.Y.Z -m "FSearch X.Y.Z"`.
- [ ] Push the tag: `git push origin vX.Y.Z`.

### 3. Build the release

CI's tag build is the release of record. Pushing a `v*` tag runs the `release` job, which waits for the `kit`, `app` and `lint` jobs, then runs `scripts/release.sh` in two phases (see [CI release job](#ci-release-job-environment-approval-provenance)). That script builds, signs, notarizes and staples the app and DMG, verifies both, and writes the SHA-256 checksum. If the repository protects the job with an environment that needs approval, approve the run.

- [ ] Watch the run finish. Download the `FSearch-dmg` artifact from the run. It holds the DMG, its `.sha256` checksum and the `.intoto.jsonl` provenance attestation.

If CI cannot run, use the fallback: on a Mac with the setup above, check out the tag and run `scripts/release.sh X.Y.Z` (both phases in one go). The output lands in `build/release/`, including `FSearch-X.Y.Z.dmg` and `FSearch-X.Y.Z.dmg.sha256`. The script also writes `release/last-build`, which is git-ignored. Keep it with your release records, or copy the last appcast's build number into it on a new Mac. The tags cover the same check when the file is missing, as in CI's fresh checkout, provided every release was tagged.

### 4. Verify the DMG

Run these on a real Mac, on the DMG from step 3.

- [ ] `spctl` accepts the DMG and the app, and `xcrun stapler validate` passes on both. The release script checks this and prints "accepted" for both.
- [ ] Sparkle's nested code is signed. `codesign -dvv` on `Sparkle.framework/Versions/B/Autoupdate` and `Updater.app` shows the Developer ID authority, a timestamp and `flags=0x10000(runtime)`. Sparkle's `XPCServices` folder must be absent, because the app is not sandboxed. See [ADR 0008](adr/0008-strip-sparkles-xpc-services.md).
- [ ] The DMG opens with FSearch.app beside an Applications shortcut.
- [ ] A fresh install (new user account) opens with no Gatekeeper warning.
- [ ] Onboarding: all four steps work, and the login item appears as FSearch.
- [ ] Confirm which program macOS lists for Full Disk Access (the app or the helper), and that the step's text matches it.
- [ ] The hotkey opens the panel. A name search, **Search inside files** and **Find definitions** all return results.
- [ ] The default hotkey is ⌥Space. If Raycast or another launcher holds it, the conflict warning appears.
- [ ] Quick Look keeps the panel open.
- [ ] Drag a result row to Finder (it copies or moves the file) and to a Mail compose window (it attaches the file).
- [ ] Open, Reveal, Quick Look, Copy Path and ⌘K work on a file whose name has spaces and an emoji.
- [ ] Open at a line works in Zed, Sublime Text and BBEdit. These are untested so far.
- [ ] Reopening the panel within 60 seconds restores the previous selection, and focus returns to the previously active app when the panel hides.
- [ ] With the CLI's daemon running (`fsearch install --login`), the app uses it and does not start a second one.
- [ ] Debug mode on: the search log fills. **Clear Log** empties it. Turning debug mode off removes the file.
- [ ] Upgrade over the previous version through Sparkle: Full Disk Access is still on, and the index was not rebuilt.
- [ ] Update test, before you publish to everyone: build a copy with a lower version (`xcodebuild ... CURRENT_PROJECT_VERSION=0`, or edit the built app's `CFBundleVersion`), install it, run `defaults delete com.domfahey.fsearch SULastCheckTime` and launch it. The update must be offered, install and relaunch. With FSearch in the background, a scheduled check changes the menu-bar icon and shows **Update Available…** instead of a window.

CI does not run the UI tests (hosted runners have no GUI session). Run them locally with `make ui` on a Mac nobody is using.

### 5. Publish the GitHub release

- [ ] Create a draft release for the tag. Paste the version's CHANGELOG section as the notes.
- [ ] Attach `FSearch-X.Y.Z.dmg` and `FSearch-X.Y.Z.dmg.sha256`.
- [ ] Publish the release once the appcast is ready (next step).

### 6. Update the appcast

The app requires a signed feed (`SURequireSignedFeed`). Never edit `appcast.xml` by hand. Run `generate_appcast` again so the feed signature is regenerated.

- [ ] Check out the `gh-pages` branch into a folder. It holds the current `appcast.xml`.
- [ ] Copy `FSearch-X.Y.Z.dmg` into that folder.
- [ ] Run `build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast <that folder>`. It reads the EdDSA private key from your Keychain and adds the new entry.
- [ ] Commit `appcast.xml` and push the `gh-pages` branch.
- [ ] Check that an older build sees the update. Run the update test from step 4 if you have not.

## Roll back or yank a release

Sparkle never downgrades an install, so the fix for a bad release is a newer one.

1. Remove the bad version's entry from the feed. Delete its DMG from the `gh-pages` folder, run `generate_appcast` on the folder again, and push `appcast.xml`. New update checks stop offering it.
2. Mark the GitHub release as a pre-release or delete it, and say why in the notes. Do not reuse its version number or build number.
3. Fix the problem and release the next version through this runbook. Installs of the bad version update to it.

## Homebrew cask

A Homebrew cask is planned for after the first release. It will point at the release DMG and its SHA-256, and include a `zap` stanza for the data and log folders. See [To do](todos.md).

## CI release job (environment approval, provenance)

CI release flow. Push a tag only on a commit of `main` (the job refuses any other tag). The `release` job waits for approval of the `release` environment, then builds everything before it touches a secret: the daemon with `cargo build --locked` on the pinned Rust toolchain (`RUST_TOOLCHAIN` in `ci.yml`), the Xcode project, the Swift packages (resolved from `Package.resolved` only) and the unsigned archive (`scripts/release.sh --prepare`). Only then does it unlock the signing keychain and run `scripts/release.sh --sign`, which signs, notarizes and packages that archive and builds or fetches nothing. It then writes a build provenance attestation and creates a draft GitHub release with the DMG, `.sha256` and `.intoto.jsonl` attestation bundle. XcodeGen is installed by `scripts/install-xcodegen.sh` from a pinned, checksum-verified release, and Swift packages resolve from the committed `Package.resolved`; when you bump a dependency or the toolchain, update those pins (and `Package.resolved`) in their own reviewed commit. Check on the downloaded DMG that `shasum -a 256 -c FSearch-<version>.dmg.sha256` and `gh attestation verify FSearch-<version>.dmg -R domfahey/fsearch-app` pass, then publish the draft.

## See also

- [Changelog](../CHANGELOG.md)
- [Contributing](../CONTRIBUTING.md)
