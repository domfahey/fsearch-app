# 0002. Bundle the fsearch daemon and run it with SMAppService

Date: 2026-10-10
Status: Accepted

## Context

The goal is that someone downloads the app, grants access once, and searches. They should never open a terminal or install a separate tool. The engine is the fsearch daemon, which must run in the background to keep the index current.

Full Disk Access is granted to a program. The program that reads the disk has to be one macOS can name and keep a grant for across updates.

## Considered options

- Ship the daemon inside the app and run it with `SMAppService`. This needs no separate install.
- Ask people to install the fsearch CLI themselves. This puts a terminal step in front of every new user.
- Link to the system's `fsearch` or run it from a path the app does not own. The app could not pin its version, and macOS would have no stable program to attach Full Disk Access to.

## Decision

Ship the daemon inside the app, at `Contents/Helpers/fsearch`. Run it as a login item with `SMAppService`, using a LaunchAgent plist inside the bundle, `com.domfahey.fsearch.daemon.plist`. The agent runs `fsearch serve`.

The daemon is built from a pinned commit by `scripts/build-daemon.sh` as a universal binary, and is signed with the app's Developer ID. While upstream changes are pending, the build uses the `domfahey/fsearch` fork. The plan is to move to an upstream tag.

The app talks to the daemon over its socket in `~/Library/Application Support/FSearch`.

## Consequences

- No separate install. macOS may ask you to approve the login item in System Settings.
- The helper starts at login, so the index is already current when you press the hotkey.
- The daemon is pinned, so the app and daemon versions match.
- Which binary macOS lists for Full Disk Access (the app or the helper) is not yet confirmed. See [Known limitations](../reference/limitations.md).
- The app must handle a daemon that is already running. See [ADR 0003](0003-never-take-over-a-daemon-the-app-did-not-start.md).
