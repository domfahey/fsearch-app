# 0006. Not on the Mac App Store

Date: 2026-10-10
Status: Accepted

## Context

The app needs Full Disk Access to index the whole disk. It also runs a bundled daemon that reads and watches files anywhere on your Mac, and it runs helper programs such as an editor's command to open a file at a line. The Mac App Store requires sandboxing, which would block this.

## Decision

Distribute the app outside the Mac App Store as a signed, notarized DMG. Sign with an Apple Developer ID, and notarize every release. Update through Sparkle, with signed update feeds. A Homebrew cask may come later.

## Consequences

- The app can index and search the whole disk.
- There is no App Store review or sandbox limit.
- Each release needs signing and notarization, handled by `scripts/release.sh` and the [release runbook](../release-checklist.md).
- People find the app through GitHub, not the store.
- Updates depend on the Sparkle key being set up. Until then, the updater stays off and **Check for Updates…** is hidden.
