# Contributing

This guide tells you how to set up, build, test and submit a change to FSearch for Mac. Please read it before you open a pull request.

By taking part you agree to follow the [Code of Conduct](.github/CODE_OF_CONDUCT.md).

## Secrets

Never commit keys, certificates, provisioning profiles, notary API keys or the Sparkle private key. Run `make hooks` once after cloning: it installs git hooks that refuse commits and pushes containing key files or secret-looking content. `.gitignore` also excludes the usual key file types. Only Sparkle's *public* key (`SUPublicEDKey`) belongs in the repo.

## Set up

You need Xcode 16 or later (Swift 6), Rust with both macOS targets, and XcodeGen. The README lists the exact steps in [Prerequisites](README.md#prerequisites).

Run `make help` to list the developer tasks used below.

## Build

From the repository root, build the pinned fsearch daemon once, then build the app:

```sh
make daemon   # scripts/build-daemon.sh
make build    # xcodegen generate, then the Debug build (the same as CI)
```

Or run the raw commands:

```sh
scripts/build-daemon.sh
xcodegen generate
xcodebuild -project FSearch.xcodeproj -scheme FSearch -configuration Debug \
  -derivedDataPath build -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY=- build
```

## Run the tests

| Task | Command | Raw equivalent |
|---|---|---|
| Core tests | `make test` | `cd Packages/FSearchKit && swift test` |
| Lint (swift-format, credits, shell scripts, workflows) | `make lint` | see the `lint` target in the [Makefile](Makefile) |
| Warnings as errors | `make type` | `swift build --build-tests -Xswiftc -warnings-as-errors` in the package, plus a warnings check of the app build |
| Benchmarks | `make bench` | `scripts/bench.sh` |
| Lint, type and test together | `make check` | |
| Everything CI runs, with the coverage gates | `make ci` | |
| Check developer prerequisites | `make doctor` | |
| Install developer prerequisites (not the app) | `make install` | `brew install xcodegen`, `rustup target add aarch64-apple-darwin x86_64-apple-darwin`, `make hooks` |
| Remove build outputs / also the daemon and generated project | `make clean` / `make distclean` | |

- Core tests need `Vendor/fsearch` from `make daemon`.
- Markdown links: `scripts/check-links.sh` checks that every relative link and anchor resolves. CI runs it, so run it when you edit docs.
- UI smoke test: `make ui` (`scripts/ui-smoke.sh`). It needs a logged-in GUI session and accessibility permission for the test runner. CI does not run it, so run it locally when you change the panel.

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
- Formatting is checked by `swift format` with the repository's `.swift-format` config. `make format` applies it.

## Tests

- New behaviour needs a test that fails without it.
- Coverage: CI fails if FSearchKit line coverage drops below 90% (`scripts/coverage.sh --kit-only --min 90`) or if AppTests-only app coverage (excluding documented system adapters) drops below 80%. The full app number, combining AppTests with the UI tests, needs a GUI session: run `make coverage` locally (`--min 90` gates it).
- Tests must never touch the real index, `~/Library/LaunchAgents`, `~/.local/bin` or `~/Library/Application Support/FSearch`.
- Use a temporary `HOME` and `FSEARCH_ROOT` for anything that starts a daemon. In the core tests, use `RealDaemon`: it runs the daemon under a watchdog that stops it and deletes its temporary directory when the test process exits or crashes, and it sweeps orphans from earlier hard-killed runs. See [ADR 0005](docs/adr/0005-tests-never-touch-the-real-index.md).

## Commit messages

- Write the subject in the imperative mood, such as "Fix follower wait". Keep it short.
- Use the body to say why the change is needed.

## Branches and pull requests

- One topic per pull request.
- CI must be green.
- Run `make check` and `scripts/check-links.sh` first.
- Update [CHANGELOG.md](CHANGELOG.md) under Unreleased.
- Fill in the pull request template.

## Reporting bugs and ideas

Use the issue templates. For a bug, include the Index Details output from debug mode and remove private paths first. Report security problems privately. See [Security](.github/SECURITY.md).

## Updating dependencies

- GitHub Actions are pinned to full commit SHAs, each with a version comment. Dependabot updates them weekly. Only pin a release that is at least two weeks old.
- The app's Swift packages (KeyboardShortcuts and Sparkle) are declared in `project.yml` for XcodeGen. Dependabot cannot read that file. Bump `exactVersion` there by hand, again choosing a release at least two weeks old, and update [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) to match.
- `Packages/FSearchKit` has no dependencies.
- The fsearch daemon is pinned by commit in `scripts/build-daemon.sh`.

## License

There is no CLA or DCO. By contributing, you agree that your work is released under the [MIT License](LICENSE).

## See also

- [Architecture](docs/architecture.md)
- [Release checklist](docs/release-checklist.md)
- [Documentation hub](docs/README.md)
