# FSearch for Mac

FSearch for Mac is a Spotlight-style launcher for the fsearch file-search daemon. It targets macOS 14 and later.

## Prerequisites

- Xcode 16 or later (Swift 6). CI uses Xcode 26.6; on this machine it is selected with `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (Xcode 26.6).
- Rust via [rustup](https://rustup.rs), with both macOS targets: `rustup target add aarch64-apple-darwin x86_64-apple-darwin`.
- XcodeGen: `brew install xcodegen`.

## Build and test

Run these from the repository root, in order:

1. `scripts/build-daemon.sh` builds the pinned fsearch daemon as a universal binary into `Vendor/fsearch`. Everything below needs it.
2. `xcodegen generate` generates `FSearch.xcodeproj`.
3. Build the universal app (the same command CI runs):

   ```sh
   xcodebuild -project FSearch.xcodeproj -scheme FSearch -configuration Debug \
     -derivedDataPath build -destination 'generic/platform=macOS' \
     CODE_SIGN_IDENTITY=- build
   ```

4. `cd Packages/FSearchKit && swift test` runs the core tests. They run against the real daemon, so `Vendor/fsearch` must exist first.
5. `scripts/ui-smoke.sh` runs the panel UI smoke test (AppUITests) against a throwaway daemon. It needs a logged-in GUI session and accessibility permission for the test runner, so it doesn't run in CI or over SSH.

Tests never touch your real index: the core tests and the UI smoke test start their own daemon with a temporary `HOME` and `FSEARCH_ROOT`, and the app's test mode never registers the login daemon.

Releases: `scripts/release.sh` and [docs/release-checklist.md](docs/release-checklist.md).

The design spec is in `docs/superpowers/specs/` and the implementation plan is in `docs/superpowers/plans/`.

## License

MIT. See [LICENSE](LICENSE).
