## Summary

<!-- What changes, and why? -->

## Linked issue

<!-- For example: Fixes #123. Write "none" if there is no issue. -->

## How was this tested?

- [ ] `make check` (lint, type and FSearchKit tests; it includes `scripts/check-links.sh`)
- [ ] `make apptest` (AppTests), if I changed code under `App/`
- [ ] `make ui` (UI tests), if I changed the panel. **These tests type on the keyboard: I ran them on a Mac nobody was using.**
- [ ] Manual (describe below)

<!-- Notes on manual testing. -->

## Screenshots

<!-- For UI changes, add before and after screenshots. Write "none" otherwise. -->

## Checklist

- [ ] I added or changed tests. New behavior has a test that fails without it.
- [ ] The build has zero warnings.
- [ ] I updated `CHANGELOG.md` under Unreleased.
- [ ] No test touches the real index, `~/Library/Application Support/FSearch`, `~/Library/LaunchAgents` or `~/.local/bin`.
- [ ] I updated the docs (README, CONTRIBUTING, `docs/`) if needed.
