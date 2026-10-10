# Release checklist

## One-time user steps (not automated)

- [ ] Generate the Sparkle EdDSA key pair: run Sparkle's `generate_keys` (from the Sparkle package's `bin/`). The private key goes in your Keychain; put the printed public key in `SUPublicEDKey` in `App/Resources/Info.plist`. Until this is done the key is `REPLACE_WITH_SPARKLE_PUBLIC_KEY`, the updater is not started, "Check for Updates…" is hidden, and `scripts/release.sh` refuses to run.
- [ ] Developer ID Application certificate installed; `export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"`.
- [ ] `xcrun notarytool store-credentials fsearch-notary`.
- [ ] Set up the GitHub Pages site behind `SUFeedURL` (`https://domfahey.github.io/fsearch-app/appcast.xml`) once.
- [ ] Before merging: watch the first real CI run (kit, app) pass on GitHub.
- [ ] For tag builds in CI: add repo secrets `DEVELOPER_ID`, `DEVELOPER_ID_CERT_P12_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`, `KEYCHAIN_PASSWORD`, and an App Store Connect API key for notarytool: `NOTARY_API_KEY_P8_BASE64` (the .p8, base64), `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`.

## Per release

Run on a real Mac, on the DMG produced by `scripts/release.sh`.

- [ ] Before building: bump `CFBundleShortVersionString` and `CFBundleVersion` in `App/Resources/Info.plist`.

- [ ] First real release run only: verify the signing of Sparkle's nested code. `codesign -dvv` on `Sparkle.framework/Versions/B/{Autoupdate,Updater.app,XPCServices/Installer.xpc,XPCServices/Downloader.xpc}` shows the Developer ID authority, a timestamp and `flags=0x10000(runtime)`; `codesign -d --entitlements - .../Downloader.xpc` matches what the Sparkle package shipped (an empty dict as of 2.x via SPM); the `--deep --strict` verify passed.
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
- [ ] After verifying: run Sparkle's `generate_appcast` on `build/release` (it reads the EdDSA private key from your Keychain) and publish `appcast.xml` plus the DMG to the `SUFeedURL` GitHub Pages site; check that an older build sees the update.

CI does not run the UI tests (no GUI session on hosted runners); run them locally.
