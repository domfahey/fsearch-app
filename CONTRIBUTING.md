# Contributing

This guide tells you how to set up, build, test and submit a change to FSearch for Mac. Please read it before you open a pull request.

By taking part you agree to follow the [Code of Conduct](.github/CODE_OF_CONDUCT.md).

## Secrets

Never commit keys, certificates, provisioning profiles, notary API keys or the Sparkle private key. Run `make hooks` once after cloning: it installs git hooks that refuse commits and pushes containing key files or secret-looking content. `.gitignore` also excludes the usual key file types. Only Sparkle's *public* key (`SUPublicEDKey`) belongs in the repo. If a hook refuses your commit, remove the secret. Don't skip the hooks with `--no-verify`: git allows it, but this project doesn't, and a false positive is a reason to fix the pattern in `scripts/hooks/check-secrets.sh` instead.

## Set up

### Prerequisites

- **Xcode 16 or later** (Swift 6). The app is tested with Xcode 26.6. FSearchKit is tested with Xcode 16.2 and later. The Makefile and scripts use `DEVELOPER_DIR` if it is set, otherwise the Xcode that `xcode-select -p` reports. Select one with `sudo xcode-select -s /Applications/Xcode.app`, or `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- **Rust** through [rustup](https://rustup.rs), with both macOS targets: `rustup target add aarch64-apple-darwin x86_64-apple-darwin`.
- **XcodeGen**: `scripts/install-xcodegen.sh ~/.local/share/xcodegen` installs the pinned, checksum-verified release that CI uses (it empties that folder first) and prints its `bin` folder; add that folder to your `PATH`. `brew install xcodegen` (what `make install` runs) also works, but its version floats.
- **python3**, which `scripts/check-links.sh` uses. macOS and Xcode's command-line tools provide it.
- **Network access** the first time you build the daemon. `scripts/build-daemon.sh` clones the pinned fsearch commit from GitHub.
- Optional: `shellcheck` and `actionlint`. `make lint` skips them with a message when they are missing. CI runs both.

Run `make doctor` to check all of this. Run `make install` to install the developer tools and git hooks. It does not install the app.

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
  -derivedDataPath build -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY=- build
```

## Where does my change go

| Kind of change | Where it goes |
|---|---|
| Pure logic with no UI or system calls, such as query splitting, the wire format, the search model and the daemon plan | `Packages/FSearchKit`, with unit tests there |
| Glue between the app and macOS, such as the panel, menus, onboarding, settings and the updater | `App/` |
| A call to something macOS owns, such as `SMAppService`, `NSWorkspace`, the Trash or Sparkle | A protocol (a seam) in `App/Support/Seams.swift` or `SystemSeams.swift`. Add a fake to `AppTests/Support/Fakes.swift` and test against it. |
| A test of app code | `AppTests/` |
| A test that drives the real UI | `AppUITests/` (see the focus-safety rule below) |

Two modes keep tests away from your real setup. **Test mode** starts when you pass `-FSEARCH_SOCKET <path>`. The app then talks to that throwaway daemon and never touches the login item or shows onboarding. The **inert host** is the app when it hosts AppTests: it starts no helper, hotkey, onboarding or updater, and it points at a socket nobody listens on. See [ADR 0007](docs/adr/0007-test-seams-inert-test-host-and-test-mode.md) and [ADR 0005](docs/adr/0005-tests-never-touch-the-real-index.md).

## Test tiers

| Tier | Run it | Safe to run while you work? | In CI? |
|---|---|---|---|
| FSearchKit unit and integration tests, against a real daemon in a temporary `HOME` | `make test` | Yes | Yes, on macOS 14 and macOS 26 |
| AppTests, the app's unit tests, in an inert host with fakes | `make apptest` or `scripts/coverage.sh --unit-only` | Yes. The host shows nothing and takes no focus. | Yes, with an 80% coverage gate |
| UI and end-to-end tests (AppUITests) | `make ui` | No. It synthesizes keystrokes. Use a hands-off GUI session. | No |
| Benchmarks | `scripts/bench.sh --report-only --skip-daemon` (or `make bench` for the full run) | Yes | Report-only |

**Focus-safety rule.** AppTests must never show a window, take the keyboard or bring FSearch to the front, because you may be working at the Mac. A test that needs real focus or keystrokes belongs in AppUITests. While AppUITests run, leave the Mac alone.

## Other tasks

| Task | Command | Raw equivalent |
|---|---|---|
| Lint (swift-format, links, credits, shell scripts, workflows) | `make lint` | see the `lint` target in the [Makefile](Makefile) |
| Warnings as errors | `make type` | `swift build --build-tests -Xswiftc -warnings-as-errors` in the package, plus a warnings check of the app build |
| Lint, type and test together | `make check` | |
| Everything CI runs, with the coverage gates | `make ci` | |
| Coverage of FSearchKit only | `make coverage-kit` | `scripts/coverage.sh --kit-only` |
| Coverage of both app suites plus FSearchKit | `make coverage` | `scripts/coverage.sh` |
| Check developer prerequisites | `make doctor` | |
| Install developer prerequisites (not the app) | `make install` | `brew install xcodegen`, `rustup target add aarch64-apple-darwin x86_64-apple-darwin`, `make hooks` |
| Remove build outputs / also the daemon and generated project | `make clean` / `make distclean` | |

- `make test` needs `Vendor/fsearch` from `make daemon`, and builds it if it is missing.
- `make lint` ends with `lint: ok` when everything passes. The checks print nothing of their own on success. It includes `scripts/check-links.sh`, which checks that every relative Markdown link and anchor resolves. CI runs it, so run it when you edit docs.

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

## Tests

- New behavior needs a test that fails without it.
- Coverage gates: CI fails if FSearchKit line coverage drops below 90% (`scripts/coverage.sh --kit-only --min 90`) or if AppTests-only app coverage (excluding documented system adapters) drops below 80% (`scripts/coverage.sh --unit-only --min 80`). `make ci` runs both gates. To try a different floor, pass `--min` or set `COVERAGE_MIN`, for example `scripts/coverage.sh --kit-only --min 90` or `COVERAGE_MIN=90 scripts/coverage.sh --kit-only`. The full app number, which combines AppTests with the UI tests, needs a hands-off GUI session: run `make coverage`.
- Tests must never touch the real index, `~/Library/LaunchAgents`, `~/.local/bin` or `~/Library/Application Support/FSearch`.
- Use a temporary `HOME` and `FSEARCH_ROOT` for anything that starts a daemon. In the core tests, use `RealDaemon`: it runs the daemon under a watchdog that stops it and deletes its temporary directory when the test process exits or crashes, and it sweeps orphans from earlier hard-killed runs. See [ADR 0005](docs/adr/0005-tests-never-touch-the-real-index.md).

## Commit messages

- Write the subject in the imperative mood, such as "Fix follower wait". Keep it short.
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
| `make lint` seems to print nothing | On success it ends with `lint: ok`. A skipped check says so, for example "shellcheck not installed; skipped". |
| `make doctor` reports a failed check | Follow the `fix:` line under it. |

## Updating dependencies

- GitHub Actions are pinned to full commit SHAs, each with a version comment. Dependabot updates them weekly. Only pin a release that is at least two weeks old.
- The app's Swift packages (KeyboardShortcuts and Sparkle) are declared in `project.yml` for XcodeGen. Dependabot cannot read that file. Bump `exactVersion` there by hand, again choosing a release at least two weeks old, and update [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) to match. Then run `scripts/gen-credits.sh` to rebuild the About window credits, which `make lint` checks.
- `Packages/FSearchKit` has no dependencies.

### Bumping the daemon pin

The fsearch daemon is pinned by commit in `scripts/build-daemon.sh` (the `REV=` line). See [ADR 0010](docs/adr/0010-pin-the-daemon-to-a-fork-commit.md) for why. To move the pin:

1. Change `REV` in `scripts/build-daemon.sh` to the new commit.
2. Run `make daemon`, then `make check`. `make doctor` confirms `Vendor/fsearch` matches the pin.
3. Re-record this machine's benchmark baseline with `scripts/bench.sh --record` if performance moved on purpose. See [bench/README.md](bench/README.md).
4. Update the daemon's commit in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), then run `scripts/gen-credits.sh`.
5. Add a line to [CHANGELOG.md](CHANGELOG.md) under Unreleased if users can see the change.

## License

There is no CLA or DCO. By contributing, you agree that your work is released under the [MIT License](LICENSE).

## See also

- [Architecture](docs/architecture.md)
- [Release runbook](docs/release-checklist.md)
- [Documentation hub](docs/README.md)
