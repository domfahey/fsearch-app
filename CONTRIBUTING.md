# Contributing

Thanks for helping. This guide is short. Please read it before you open a pull request.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Set up

You need Xcode 16 or later (Swift 6), Rust with both macOS targets, and XcodeGen. The README lists the exact steps in [Prerequisites](README.md#prerequisites).

## Build

From the repository root:

```sh
scripts/build-daemon.sh
xcodegen generate
xcodebuild -project FSearch.xcodeproj -scheme FSearch -configuration Debug \
  -derivedDataPath build -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY=- build
```

## Run the tests

- Core tests: `cd Packages/FSearchKit && swift test`. They need `Vendor/fsearch` from `scripts/build-daemon.sh`.
- UI smoke test: `scripts/ui-smoke.sh`. It needs a logged-in GUI session and accessibility permission for the test runner. CI does not run it, so run it locally when you change the panel.

## Running your own build

- **Signing.** `project.yml` sets `CODE_SIGN_IDENTITY: "-"`, so local builds are ad-hoc signed. That is fine for development, and it needs no certificate.
- **Permissions.** macOS ties Full Disk Access and the login item to an app's code signature, so an ad-hoc build is a different app to macOS than the released one. Grant Full Disk Access to your build on its own, and expect to grant it again after you rebuild. Onboarding walks you through it.
- **Releases.** Developer ID signing and notarization live only in [`scripts/release.sh`](scripts/release.sh). They need the maintainer's credentials (`DEVELOPER_ID`, a `notarytool` profile and the Sparkle key), so you cannot produce a release build.
- **Avoid clashing with other installs.** The app uses whichever daemon answers on `~/Library/Application Support/FSearch/fsearch.sock`, and it will not replace one it did not start. If the released FSearch or the `fsearch` CLI daemon is running, your build talks to that daemon. Your build also has the same bundle ID and login-agent label as the release, so quit the release app first. To run against a throwaway daemon, start one with a temporary `HOME` and `FSEARCH_ROOT` (see [`scripts/ui-smoke.sh`](scripts/ui-smoke.sh)) and launch the app with `-FSEARCH_SOCKET <that socket>`. In that test mode the app never registers the login item or restarts a daemon. See [ARCHITECTURE.md](ARCHITECTURE.md).
- **Never run tests against your real index.** See [Tests](#tests).

## Code style

- Swift 6. The build must have zero warnings.
- Indent with 4 spaces in Swift, and 2 spaces in YAML and JSON. This is set in `.editorconfig`.
- Use LF line endings and end files with a newline.
- Keep comments short. Explain why, not what.
- There is no `.swift-format` config in the repo yet. Match the style of the code around your change.

## Tests

- New behaviour needs a test that fails without it.
- Tests must never touch the real index, `~/Library/LaunchAgents`, `~/.local/bin` or `~/Library/Application Support/FSearch`.
- Use a temporary `HOME` and `FSEARCH_ROOT` for anything that starts a daemon.

## Commit messages

- Write the subject in the imperative mood, such as "Fix follower wait". Keep it short.
- Use the body to say why the change is needed.

## Branches and pull requests

- One topic per pull request.
- CI must be green.
- Update [CHANGELOG.md](CHANGELOG.md) under Unreleased.
- Fill in the pull request template.

## Reporting bugs and ideas

Use the issue templates. For a bug, include the Index Details output from debug mode and remove private paths first. Report security problems privately. See [SECURITY.md](SECURITY.md).

## Updating dependencies

- GitHub Actions are pinned to full commit SHAs, each with a version comment. Dependabot updates them weekly. Only pin a release that is at least two weeks old.
- The app's Swift packages (KeyboardShortcuts and Sparkle) are declared in `project.yml` for XcodeGen. Dependabot cannot read that file. Bump `exactVersion` there by hand, again choosing a release at least two weeks old, and update [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) to match.
- `Packages/FSearchKit` has no dependencies.
- The fsearch daemon is pinned by commit in `scripts/build-daemon.sh`.

## License

There is no CLA or DCO. By contributing, you agree that your work is released under the [MIT License](LICENSE).
