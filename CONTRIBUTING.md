# Contributing

This guide tells you how to set up, build, test and submit a change to FSearch for Mac. Please read it before you open a pull request.

By taking part you agree to follow the [Code of Conduct](.github/CODE_OF_CONDUCT.md).

## Secrets

Never commit keys, certificates, provisioning profiles, notary API keys or the Sparkle private key. Run `make hooks` once after cloning: it installs git hooks that refuse commits and pushes containing key files or secret-looking content. `.gitignore` also excludes the usual key file types. Only Sparkle's *public* key (`SUPublicEDKey`) belongs in the repo. If a hook refuses your commit, remove the secret. Don't skip the hooks with `--no-verify`: git allows it, but this project doesn't, and a false positive is a reason to fix the pattern in `scripts/hooks/check-secrets.sh` instead.

## Set up

### Prerequisites

- **macOS 15 or later** (`make doctor` checks it).
- **Xcode 16 or later** (Swift 6). The app and FSearchKit are tested with Xcode 26.6. The Makefile and scripts use `DEVELOPER_DIR` if it is set, otherwise the Xcode that `xcode-select -p` reports. Select one with `sudo xcode-select -s /Applications/Xcode.app`, or `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- **Rust** through [rustup](https://rustup.rs), with both macOS targets: `rustup target add aarch64-apple-darwin x86_64-apple-darwin`.
- **XcodeGen**: `scripts/install-xcodegen.sh ~/.local/share/xcodegen` installs the pinned, checksum-verified release that CI uses (it empties that folder first) and prints its `bin` folder; add that folder to your `PATH`. `brew install xcodegen` also works, but its version floats. `make install` runs it only if `xcodegen` is missing.
- **python3**, which `scripts/check-links.sh` uses. macOS and Xcode's command-line tools provide it.
- **Network access** the first time you build the daemon. `scripts/build-daemon.sh` clones the pinned fsearch commit from GitHub.
- Optional: `shellcheck` and `actionlint`. `make lint` skips them with a message when they are missing. CI runs both. `OPTIONAL=1 make install` installs both with Homebrew.

Run `make doctor` to check all of this. Run `make install` to install the developer tools and git hooks, and finish with `make doctor`. It does not install the app, and it does not build the daemon, so `make doctor` stays red until you run `make daemon`.

Run `make help` to list the developer tasks used below.

## Build

From the repository root, build the pinned fsearch daemon once, then build the app:

```sh
make daemon   # scripts/build-daemon.sh
make build    # generate the project (pinned packages), then the Debug build (the same as CI)
```

Or run the raw commands:

```sh
scripts/build-daemon.sh
scripts/generate-project.sh   # xcodegen generate + the committed Package.resolved
xcodebuild -project FSearch.xcodeproj -scheme FSearch -configuration Debug \
  -onlyUsePackageVersionsFromResolvedFile -derivedDataPath build \
  -destination 'generic/platform=macOS' CODE_SIGN_IDENTITY=- build
```

## Where does my change go

| Kind of change | Where it goes |
|---|---|
| Pure logic with no UI or system calls, such as query splitting, the wire format, the search model and the daemon plan | `Packages/FSearchKit`, with unit tests there |
| Glue between the app and macOS, such as the panel, menus, onboarding, settings and the updater | `App/` |
| A call to something macOS owns, such as `SMAppService`, `NSWorkspace`, the Trash or Sparkle | A protocol (a seam) in `App/Support/Seams.swift` or `SystemSeams.swift`. Add a fake to `AppTests/Support/Fakes.swift` and test against it. |
| A test of app code | `AppTests/`. For a view, render it off screen with `render(_:)` and read or press it through its accessibility tree (`axNode`, in `AppTests/Support/Accessibility.swift`). Never press a button that opens a real window or quits. |
| An App Intent for Shortcuts | `App/Intents/`. Test it in `AppTests/AppIntentsTests.swift` by swapping the intent's `backendFactory` seam (`App/Intents/SearchFilesIntent.swift`) for a fake. See [Shortcuts](docs/reference/shortcuts.md). |
| A user-facing string | Swift source, then `make strings` to update the two String Catalogs (see [Localization](#localization)) |
| A test that drives the real UI | `AppUITests/` (see the focus-safety rule below) |

Two modes keep tests away from your real setup. **Test mode** starts when you pass `-FSEARCH_SOCKET <path>`. The app then talks to that throwaway daemon and never touches the login item or shows onboarding. The **inert host** is the app when it hosts AppTests: it starts no helper, hotkey, onboarding or updater, and it points at a socket nobody listens on. See [ADR 0007](docs/adr/0007-test-seams-inert-test-host-and-test-mode.md) and [ADR 0005](docs/adr/0005-tests-never-touch-the-real-index.md).

## Test tiers

| Tier | Run it | Safe to run while you work? | In CI? |
|---|---|---|---|
| FSearchKit unit and integration tests, against a real daemon in a temporary `HOME` | `make test` | Yes | Yes, on macOS 26 with a 95% coverage gate |
| AppTests, the app's unit tests, in an inert host with fakes | `make apptest` or `scripts/coverage.sh --unit-only` | Yes. The host shows nothing and takes no focus. | Yes, with a 95% coverage gate |
| UI and end-to-end tests (AppUITests, 28 tests, ~2 min) | `make ui` | No. It synthesizes keystrokes. Use a hands-off GUI session. | No |
| Benchmarks | `scripts/bench.sh --report-only --skip-daemon` (or `make bench` for the full run) | Yes | Yes, gated against `ci-macos-26` (warns on busy runner) |

**Focus-safety rule.** AppTests must never show a window, take the keyboard or bring FSearch to the front, because you may be working at the Mac. A test that needs real focus or keystrokes belongs in AppUITests. While AppUITests run, leave the Mac alone.

## Other tasks

| Task | Command | Raw equivalent |
|---|---|---|
| Lint (swift-format, links, credits, appcast checks, shell scripts, workflows) | `make lint` | see the `lint` target in the [Makefile](Makefile) |
| Warnings as errors | `make type` | `swift build --build-tests -Xswiftc -warnings-as-errors` and `swift build --product FSearchBench -Xswiftc -warnings-as-errors` in the package, plus a warnings check of the app build |
| Lint, type and test together | `make check` | |
| Lint, type, test and both 95% coverage gates (excludes `bench`) | `make ci` | |
| Coverage of FSearchKit only | `make coverage-kit` | `scripts/coverage.sh --kit-only` |
| Coverage of FSearchKit and both app suites | `make coverage` | `scripts/coverage.sh` |
| Check developer prerequisites | `make doctor` | |
| Sync App and FSearchKit String Catalogs | `make strings` | `scripts/sync-strings.sh` |
| Install developer prerequisites (not the app) | `make install` | `brew install xcodegen`, `rustup target add aarch64-apple-darwin x86_64-apple-darwin`, `make hooks` |
| Remove build outputs / also the daemon and generated project | `make clean` / `make distclean` | |

- `make test` needs `Vendor/fsearch` from `make daemon`, and builds it if it is missing.
- `make lint` ends with `lint: ok` when everything passes. Most checks print nothing of their own on success, while `scripts/check-links.sh` prints its Markdown file count. `check-links.sh` checks that every relative Markdown link and anchor resolves. CI runs it, so run it when you edit docs.

- [`.github/workflows/deps.yml`](.github/workflows/deps.yml) scans the dependencies in CI. It runs `cargo-deny` on the daemon's crates (policy in [`.github/cargo-deny.toml`](.github/cargo-deny.toml): advisories, yanked crates, sources and bans) and `osv-scanner` on the daemon's `Cargo.lock` and `Package.resolved`. It runs on pull requests, on pushes to `main` and weekly. It reads lockfiles only and builds nothing. If it flags a crate, bump the pin or, with a reason, add an exception to `cargo-deny.toml` in the same pull request.
- [`scripts/test-appcast-verify.sh`](scripts/test-appcast-verify.sh) checks that `scripts/appcast.sh` refuses to sign an unverified DMG and ignores a `generate_appcast` on `PATH`. It uses a fake DMG and stub tools and signs nothing. Both `make lint` and CI's `lint` job run it.

## Running your own build

- **Signing.** `project.yml` sets `CODE_SIGN_IDENTITY: "-"`, so local builds are ad-hoc signed. That is fine for development, and it needs no certificate.
- **Permissions.** macOS ties Full Disk Access and the login item to an app's code signature, so an ad-hoc build is a different app to macOS than the released one. Grant Full Disk Access to your build on its own, and expect to grant it again after you rebuild. Onboarding walks you through it.
- **Releases.** Developer ID signing and notarization live only in [`scripts/release.sh`](scripts/release.sh). They need the maintainer's credentials (`DEVELOPER_ID`, a `notarytool` profile and the Sparkle key), so you cannot produce a release build.
- **Avoid clashing with other installs.** The app uses whichever daemon answers on `~/Library/Application Support/FSearch/fsearch.sock`, and it will not replace one it did not start. If the released FSearch or the `fsearch` CLI daemon is running, your build talks to that daemon. Your build also has the same bundle ID and login-agent label as the release, so quit the release app first. To run against a throwaway daemon, start one with a temporary `HOME` and `FSEARCH_ROOT` (see [`scripts/ui-smoke.sh`](scripts/ui-smoke.sh)) and launch the app with `-FSEARCH_SOCKET <that socket>`. In that test mode the app never registers the login item or restarts a daemon. See [Architecture](docs/architecture.md).
- **Never run tests against your real index.** See [Tests](#tests).

## Code style

- Swift 6. The build must have zero warnings.
- Indent with 4 spaces in Swift, and 2 spaces in YAML and JSON. This is set in `.editorconfig`.
- Use LF line endings and end files with a newline.
- Keep comments short. Explain why, not what.
- Give every public FSearchKit API a `///` doc comment.
- Formatting is checked by `swift format` with the repository's `.swift-format` config. `make format` applies it.

## Localization

- Write user-facing text as SwiftUI literals (`Text("Search")`) or `String(localized:)`. In FSearchKit, pass `bundle: .module`, as in `Packages/FSearchKit/Sources/FSearchKit/Messages.swift`.
- Use `Text(verbatim:)` for technical tokens that must not be translated, such as accessibility values built from data.
- After you add or change text, run `make strings`. It does a full `xcodebuild`, so it takes a while. It syncs both String Catalogs from the compiler output.
- Commit both catalogs: `App/Resources/Localizable.xcstrings` and `Packages/FSearchKit/Sources/FSearchKit/Resources/Localizable.xcstrings`.
- `AppTests/LocalizationTests.swift` and `Packages/FSearchKit/Tests/FSearchKitTests/LocalizationTests.swift` check that the catalogs are compiled into the bundles and resolve in English.

## URL scheme and App Intents

The `fsearch://search?q=` URL scheme ([URL scheme](docs/reference/url-scheme.md)) and the Search Files intent ([Shortcuts](docs/reference/shortcuts.md)) are tested in layers:

- Parsing and query logic live in FSearchKit (`SearchURL`, `ShortcutSearch`), with tests in `Packages/FSearchKit/Tests/FSearchKitTests/SearchURLTests.swift` and `ShortcutSearchTests.swift`.
- The app delegate's URL handling is tested in `AppTests/URLSchemeTests.swift`.
- The intent's `backendFactory` seam (`App/Intents/SearchFilesIntent.swift`) lets `AppTests/AppIntentsTests.swift` run it against a fake backend, never your real daemon.
- To try it by hand, start a throwaway daemon (see [Running your own build](#running-your-own-build)), launch a Debug build with `-FSEARCH_SOCKET <throwaway socket>`, then run `open 'fsearch://search?q=hello'`.

## Tests

- New behavior needs a test that fails without it.
- Coverage gates: CI fails if FSearchKit line coverage drops below 95% (`scripts/coverage.sh --kit-only --min 95`) or if AppTests-only app coverage (excluding documented system adapters) drops below 95% (`scripts/coverage.sh --unit-only --min 95`). See [ADR 0012](docs/adr/0012-coverage-gates-at-95.md). `make ci` runs both gates. To try a different floor, pass `--min` or set `COVERAGE_MIN`, for example `scripts/coverage.sh --kit-only --min 90` or `COVERAGE_MIN=90 scripts/coverage.sh --kit-only`. The full app number, which combines AppTests with the UI tests, needs a hands-off GUI session: run `make coverage`.
- Tests must never touch the real index, `~/Library/LaunchAgents`, `~/.local/bin` or `~/Library/Application Support/FSearch`.
- Use a temporary `HOME` and `FSEARCH_ROOT` for anything that starts a daemon. In the core tests, use `RealDaemon`: it runs the daemon under a watchdog that stops it and deletes its temporary directory when the test process exits or crashes, and it sweeps orphans from earlier hard-killed runs. See [ADR 0005](docs/adr/0005-tests-never-touch-the-real-index.md).

## Commit messages

- Write the subject in the imperative mood, such as "Fix follower wait". Keep it short.
- An optional capitalised area prefix is common, such as `Panel:`, `Docs:`, `Tests:` or `CI:`. Dependabot uses lowercase `ci:`. Squash merges append the pull request number, as in `(#32)`.
- Use the body to say why the change is needed.

## Branches and pull requests

- One topic per pull request.
- CI must be green.
- Run `make check` first. It includes the link check (`scripts/check-links.sh`).
- If you changed the app, run `make apptest`.
- Update [CHANGELOG.md](CHANGELOG.md) under Unreleased.
- Fill in the pull request template. Include screenshots for UI changes.

## Reporting bugs and ideas

Use the issue templates. For a bug, include the Index Details output from debug mode and remove private paths first. Report security problems privately. See [Security](.github/SECURITY.md).

## Troubleshooting your setup

| You see | What to do |
|---|---|
| A Rust error about a missing target when you build the daemon | Run `rustup target add aarch64-apple-darwin x86_64-apple-darwin`, or `make install`. |
| `xcodegen: command not found` | Run `scripts/install-xcodegen.sh ~/.local/share/xcodegen` and add the `bin` folder it prints to your `PATH`, or `brew install xcodegen`. |
| The Xcode build fails in the embed phase and tells you to run `scripts/build-daemon.sh` | `Vendor/fsearch` is missing. Run `make daemon`. |
| Swift 6 strict-concurrency errors | Fix the isolation: mark the type `@MainActor` or `Sendable`, or move the work off the main actor. Do not turn the checks down. |
| A git hook refuses your commit with "secret check" | Remove the key or token from the change. Don't use `--no-verify`; if it's a false positive, fix the pattern in `scripts/hooks/check-secrets.sh`. |
| Your build lost Full Disk Access after a rebuild | An ad-hoc build is a new app to macOS each time. Turn the entry off and on, or remove and re-add it. See [Running your own build](#running-your-own-build). |
| `make lint` seems to print almost nothing | On success most checks stay quiet (aside from `scripts/check-links.sh`'s file count) and the target ends with `lint: ok`. A skipped check says so, for example "shellcheck not installed; skipped". |
| `make doctor` reports a failed check | Follow the `fix:` line under it. |

## Updating dependencies

- GitHub Actions are pinned to full commit SHAs, each with a version comment. Dependabot updates them weekly. Only pin a release that is at least two weeks old.
- The app's Swift packages (KeyboardShortcuts and Sparkle) are declared in `project.yml` for XcodeGen. Dependabot cannot read that file. Bump `exactVersion` there by hand, again choosing a release at least two weeks old, update the committed `Package.resolved` as below (CI and release builds pass `-onlyUsePackageVersionsFromResolvedFile`), and update [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) to match. Then run `scripts/gen-credits.sh` to rebuild the About window credits, which `make lint` checks: it fails if `App/Resources/Credits.html` is out of sync with THIRD_PARTY_NOTICES.md, or if the notices lack the pinned daemon commit or package versions.
- To update `Package.resolved`, run these from the repository root:

  ```sh
  scripts/generate-project.sh
  xcodebuild -resolvePackageDependencies -project FSearch.xcodeproj -scheme FSearch
  cp FSearch.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved Package.resolved
  ```

  `scripts/generate-project.sh` seeds the project from the old file, which is why the copy goes back the other way. Review the diff before you commit it.
- `Packages/FSearchKit` has no dependencies.

### Bumping the daemon pin

The fsearch daemon is pinned by commit in `scripts/build-daemon.sh` (the `REV=` line). See [ADR 0010](docs/adr/0010-pin-the-daemon-to-a-fork-commit.md) for why and [ADR 0013](docs/adr/0013-keep-the-daemon-on-the-fork-pin-after-upstream-closed-the-prs.md) for when it moves to an upstream tag. To move the pin:

1. Change `REV` in `scripts/build-daemon.sh` to the new commit.
2. Run `make daemon`, then `make check`. `make doctor` confirms `Vendor/fsearch` matches the pin.
3. Re-record this machine's benchmark baseline with `scripts/bench.sh --record` if performance moved on purpose. See [bench/README.md](bench/README.md).
4. Update the daemon's commit in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), then run `scripts/gen-credits.sh`. Also regenerate the Rust crate table and licence texts in that file from the new daemon `Cargo.lock` (runtime dependencies only, not build or dev dependencies).
5. Add a line to [CHANGELOG.md](CHANGELOG.md) under Unreleased if users can see the change.

## License

There is no CLA or DCO. By contributing, you agree that your work is released under the [MIT License](LICENSE).

## See also

- [Architecture](docs/architecture.md)
- [Release runbook](docs/release-checklist.md)
- [Documentation hub](docs/README.md)
