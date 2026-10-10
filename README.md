# FSearch for Mac

FSearch for Mac is a Spotlight-style launcher for the fsearch file-search daemon. It targets macOS 14 and later.

## Build

- `scripts/build-daemon.sh` builds the bundled daemon into `Vendor/`.
- `cd Packages/FSearchKit && swift test` runs the core tests.
- The app project is generated with XcodeGen: `xcodegen generate`.

The design spec is in `docs/superpowers/specs/` and the implementation plan is in `docs/superpowers/plans/`.

## License

MIT. See [LICENSE](LICENSE).
