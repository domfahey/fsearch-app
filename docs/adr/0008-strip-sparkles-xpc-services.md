# 0008. Strip Sparkle's XPC services (not sandboxed)

Date: 2026-10-10
Status: Accepted

## Context

Sparkle ships two XPC services inside its framework, `Installer.xpc` and `Downloader.xpc`. They exist for sandboxed apps, which cannot install updates or reach the network on their own. FSearch is not sandboxed (see [ADR 0006](0006-not-on-the-mac-app-store.md)), so it never uses them.

Every extra code bundle in the app must be signed and notarized.

## Considered options

- Keep the XPC services. They would be signed and shipped, but never used.
- Delete them in an Xcode build phase. This does not hold: Xcode embeds the framework after post-build scripts run, so an incremental build puts them back.
- Delete them in `scripts/release.sh`, just before signing. This is the choice below.

## Decision

`scripts/release.sh` deletes `XPCServices` from the Sparkle framework before it signs the app inside-out. The script fails if the folders are still there afterward. Removing them breaks the framework's seal, and the signing step that follows re-seals it.

Debug builds keep the XPC services. This is harmless.

## Consequences

- The release ships less code to sign and less that is never used.
- The strip happens in one place, the release script, so it is easy to audit.
- The release runbook checks that `XPCServices` is absent from the finished app. See the [release runbook](../release-checklist.md).
- If the app is ever sandboxed, this decision must be reversed.
