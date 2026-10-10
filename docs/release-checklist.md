# Release checklist

This checklist is for maintainers cutting a release of FSearch for Mac. Nothing has been released yet; 0.1.0 is next.

## One-time user steps (not automated)

- [ ] Generate the Sparkle EdDSA key pair: run Sparkle's `generate_keys` (from the Sparkle package's `bin/`). The private key goes in your Keychain; put the printed public key in `SUPublicEDKey` in `App/Resources/Info.plist`. Until this is done the key is `REPLACE_WITH_SPARKLE_PUBLIC_KEY`, the updater is not started, "Check for Updates…" is hidden, and `scripts/release.sh` refuses to run.
- [ ] Back up the EdDSA private key: `generate_keys -x fsearch-sparkle-private.key` exports it from the Keychain; store the file in a password manager, never in the repo. Losing it means existing installs can't update. Restore on another Mac with `generate_keys -f fsearch-sparkle-private.key`.
- [ ] Developer ID Application certificate installed; `export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"`.
- [ ] `xcrun notarytool store-credentials fsearch-notary`.
- [ ] Set up the GitHub Pages site behind `SUFeedURL` (`https://domfahey.github.io/fsearch-app/appcast.xml`) once.
- [ ] Before merging: watch the first real CI run (kit, app) pass on GitHub.
- [ ] For tag builds in CI: add repo secrets `DEVELOPER_ID`, `DEVELOPER_ID_CERT_P12_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`, `KEYCHAIN_PASSWORD`, and an App Store Connect API key for notarytool: `NOTARY_API_KEY_P8_BASE64` (the .p8, base64), `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`.

## Per release

Run on a real Mac, on the DMG produced by `scripts/release.sh`.

- [ ] Tag the release (`git tag v0.1.0`) and run `scripts/release.sh 0.1.0` (or run it on the tagged commit with no argument). It sets `CFBundleShortVersionString` from the version and `CFBundleVersion` from `git rev-list --count HEAD` (needs a full clone), and refuses to build if that number is not greater than the one in `release/last-build` (written after each successful run; keep it with your release records, or copy the last appcast's build number into it on a new machine). Debug builds say 0.1.0 (1) from `project.yml`.
  - `release/` is gitignored, so `release/last-build` exists only on the Mac that ran the last release. The CI release job starts from a fresh checkout: it has no previous value and skips the check. The policy: tag releases only on commits of `main`, whose commit count only grows, and before tagging confirm that `git rev-list --count HEAD` is greater than the `sparkle:version` of the last appcast entry. A local run still enforces the check.

- [ ] First real release run only: verify the signing of Sparkle's nested code. `codesign -dvv` on `Sparkle.framework/Versions/B/{Autoupdate,Updater.app}` shows the Developer ID authority, a timestamp and `flags=0x10000(runtime)`; the `--deep --strict` verify passed. The app is not sandboxed, so `scripts/release.sh` deletes Sparkle's `XPCServices` (Installer.xpc, Downloader.xpc) just before it signs; `ls .../Sparkle.framework/Versions/B` must not list `XPCServices`, and the script fails if they are still there. Debug builds keep them, which is harmless.
- [ ] The release script finished without error: it ran `stapler validate` on the app and DMG and `codesign --verify --deep --strict` on the app.
- [ ] `spctl` accepts the DMG and the app (the release script prints "accepted" for both).
- [ ] The DMG opens with FSearch.app beside an Applications shortcut.
- [ ] Fresh install (new user account): opens with no Gatekeeper warning.
- [ ] Onboarding: all four steps; the login item appears as FSearch; the Full Disk Access step names the binary macOS actually lists (see the Task 0 item below).
- [ ] Task 0 FDA attribution experiment: re-confirm which binary (app vs. helper daemon) macOS lists and needs Full Disk Access.
- [ ] The hotkey opens the panel; a name search, an "Inside files" search and "Find definitions" all return results.
- [ ] Default hotkey is ⌥Space; if Raycast (or another launcher) holds it, the conflict warning appears.
- [ ] Quick Look keeps the panel open (the panel doesn't hide when the preview takes focus).
- [ ] Drag a result row to Finder (copies/moves the file) and to a Mail compose window (attaches it).
- [ ] Open, Reveal, Quick Look, Copy Path and ⌘K work on a file whose name has spaces and an emoji.
- [ ] Open-at-line CLI paths for Zed, Sublime Text and BBEdit are unverified: test each against a real install.
- [ ] Resume within 60 s: reopening the panel restores the previous selection.
- [ ] Focus returns to the previously active app when the panel hides.
- [ ] Upgrade over the previous version via Sparkle: Full Disk Access is still on, and the index wasn't rebuilt.
- [ ] With the CLI's daemon running (`fsearch install --login`), the app uses it and doesn't start a second one.
- [ ] Debug mode on: the search log fills; Clear Log empties it; debug off removes the file.
- [ ] Update test (before publishing to everyone): build a copy with a lowered version (`xcodebuild ... CURRENT_PROJECT_VERSION=0`, or edit the built app's `CFBundleVersion`), install it, run `defaults delete com.domfahey.fsearch SULastCheckTime` to clear Sparkle's check timer, and launch it: the update must be offered, install and relaunch. With FSearch in the background, a scheduled check shows the menu-bar icon change and **Update Available…** instead of a window.
- [ ] After verifying: run Sparkle's `generate_appcast` on `build/release` (a local step for now, not CI; it reads the EdDSA private key from your Keychain). The app requires a signed feed (`SURequireSignedFeed`), so never hand-edit `appcast.xml` (release notes, minimum OS, phased rollout): re-run `generate_appcast` so the feed signature is regenerated. Then publish `appcast.xml`, the DMG and its `FSearch-<version>.dmg.sha256` (written by the release script; also attach both to the GitHub release) to the `SUFeedURL` GitHub Pages site; check that an older build sees the update.

CI does not run the UI tests (no GUI session on hosted runners); run them locally.

## See also

- [Changelog](../CHANGELOG.md)
- [Contributing](../CONTRIBUTING.md)

## CI release job (environment approval, provenance)

CI release flow. Push a tag only on a commit of `main` (the job refuses any other tag). The `release` job waits for approval of the `release` environment, builds the daemon first with `cargo build --locked` on the pinned Rust toolchain (`RUST_TOOLCHAIN` in `ci.yml`), then unlocks the signing keychain, signs and notarizes, writes a build provenance attestation, and creates a draft GitHub release with the DMG, `.sha256` and `.intoto.jsonl` attestation bundle. XcodeGen is installed by `scripts/install-xcodegen.sh` from a pinned, checksum-verified release, and Swift packages resolve from the committed `Package.resolved`; when you bump a dependency or the toolchain, update those pins (and `Package.resolved`) in their own reviewed commit. Check on the downloaded DMG that `shasum -a 256 -c FSearch-<version>.dmg.sha256` and `gh attestation verify FSearch-<version>.dmg -R domfahey/fsearch-app` pass, then publish the draft.
