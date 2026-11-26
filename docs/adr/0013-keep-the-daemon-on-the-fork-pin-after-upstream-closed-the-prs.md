# 0013. Keep the daemon on the fork pin after upstream closed the PRs

Date: 2026-11-26
Status: Accepted

Amends the re-pin trigger in [ADR 0010](0010-pin-the-daemon-to-a-fork-commit.md). Its decision to pin a fork commit stands.

## Context

[ADR 0010](0010-pin-the-daemon-to-a-fork-commit.md) pinned the daemon to a fork commit, `d26cf78` in `domfahey/fsearch`, and said to move to an upstream tag when pull requests #12 to #14 merged.

That will not happen. Upstream (`noahdunnagan/fsearch`) closed all three unmerged on 2026-10-12. Upstream then fixed several problems itself and published v0.2.0 (2026-10-12), v0.2.1 (2026-10-12) and v0.2.2 (2026-11-12). Upstream `main` is at v0.2.2.

The pinned commit still has something upstream lacks. `ba100f4` makes a daemon launched by a login agent (`XPC_SERVICE_NAME` is its label) stop a stray daemon and take the socket lock. In upstream v0.2.2, `src/server.rs` still makes a second daemon log "another fsearch daemon is running" and exit, and no source file mentions `XPC_SERVICE_NAME`. `ba100f4` is in `d26cf78` but not in upstream; the fork and v0.2.2 have diverged. See [ADR 0003](0003-never-take-over-a-daemon-the-app-did-not-start.md). The pin also carries the integration tests and `FSEARCH_ROOT` support that the app's tests use ([ADR 0005](0005-tests-never-touch-the-real-index.md)).

## Considered options

- Re-pin to upstream v0.2.2. It is released and maintained, but it loses the stray-daemon behavior and the test support, and the app's integration tests and benchmark have not been run against it.
- Stay on the fork commit `d26cf78`. Builds stay reproducible and the app's tests keep passing. The cost is that upstream's v0.2.1 and v0.2.2 fixes are missing and the fork must stay reachable.
- Rebase the fork onto v0.2.2 and pin the result. This could give both, but it is real work with its own risk, and upstream has already declined the original changes.

## Decision

Stay on the fork commit `d26cf78` for now.

Re-pin to an upstream tag when a release both contains the stray-daemon yield behavior (or the app no longer needs it) and passes the app's integration tests and benchmark gate. Rebasing the fork onto a newer upstream release is a separate, deliberate change.

When the pin moves, update `REV`, the benchmark baseline, the changelog and [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md) together, as ADR 0010 describes.

## Consequences

- No change to builds. `scripts/build-daemon.sh` still pins `d26cf78`.
- The app does not get upstream's v0.2.1 and v0.2.2 fixes until the fork is rebased or upstream gains the missing behavior.
- The fork stays a dependency of every build and must stay reachable.
- Wording about pending pull requests in `scripts/build-daemon.sh`, THIRD_PARTY_NOTICES.md and the [to-do list](../todos.md) is out of date and should follow this record.
