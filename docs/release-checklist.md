# Release checklist

## One-time user steps (not automated)

- [ ] Generate the Sparkle EdDSA key pair: run Sparkle's `generate_keys` (from the Sparkle package's `bin/`). The private key goes in your Keychain; put the printed public key in `SUPublicEDKey` in `App/Resources/Info.plist`. Until this is done the key is `REPLACE_WITH_SPARKLE_PUBLIC_KEY`, the updater is not started, "Check for Updates…" is hidden, and `scripts/release.sh` refuses to run.
- [ ] Developer ID Application certificate installed; `export DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"`.
- [ ] `xcrun notarytool store-credentials fsearch-notary`.
- [ ] For tag builds in CI: add repo secrets `DEVELOPER_ID`, `DEVELOPER_ID_CERT_P12_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`, `KEYCHAIN_PASSWORD`, `NOTARY_APPLE_ID`, `NOTARY_TEAM_ID`, `NOTARY_APP_PASSWORD`.

## Per release

Run on a real Mac, on the DMG produced by `scripts/release.sh`.

- [ ] `spctl` accepts the DMG (the release script prints "accepted").
- [ ] Fresh install (new user account): opens with no Gatekeeper warning.
- [ ] Onboarding: all four steps; the login item appears as FSearch; Full Disk Access as found in docs/notes/fda-attribution.md.
- [ ] Task 0 FDA attribution experiment: re-confirm which binary (app vs. helper daemon) macOS lists and needs Full Disk Access.
- [ ] The hotkey opens the panel; a name search, an "Inside files" search and "Find definitions" all return results.
- [ ] Default hotkey is ⌥Space; if Raycast (or another launcher) holds it, the conflict warning appears.
- [ ] Open, Reveal, Quick Look, Copy Path and ⌘K work on a file whose name has spaces and an emoji.
- [ ] Open-at-line CLI paths for Zed, Sublime Text and BBEdit are unverified: test each against a real install.
- [ ] Resume within 60 s: reopening the panel restores the previous selection.
- [ ] Focus returns to the previously active app when the panel hides.
- [ ] Upgrade over the previous version via Sparkle: Full Disk Access is still on, and the index wasn't rebuilt.
- [ ] With the CLI's daemon running (`fsearch install --login`), the app uses it and doesn't start a second one.
- [ ] Debug mode on: the search log fills; Clear Log empties it; debug off removes the file.

CI does not run the UI tests (no GUI session on hosted runners); run them locally.
