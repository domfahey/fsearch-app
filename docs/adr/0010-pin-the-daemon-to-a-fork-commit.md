# 0010. Pin the daemon to a fork commit until upstream merges

Date: 2026-10-10
Status: Accepted

## Context

The app bundles the fsearch daemon by Noah Dunnagan (see [ADR 0002](0002-bundle-the-fsearch-daemon-via-smappservice.md)). The app needs fixes and tests that were submitted upstream as pull requests #12 to #14. Until they merge, upstream does not have them.

The app and the daemon must match. A daemon that moves under the app can change behavior between two builds of the same app version.

## Considered options

- Build upstream's latest commit. The result changes over time and lacks the fixes the app needs.
- Build an upstream tag. No tag has the fixes yet.
- Build a fixed commit from a fork, `domfahey/fsearch`, which is upstream plus the pending fixes. This is the choice below.
- Copy the daemon's source into this repository. This hides which code is upstream's and makes it hard to send fixes back.

## Decision

`scripts/build-daemon.sh` clones the fork and checks out one full commit (`REV`). It builds a universal binary into `Vendor/fsearch` and records the commit in `Vendor/fsearch.rev`. `make doctor` checks that the two match. [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md) names the same commit and credits the upstream project.

When the pull requests merge, move the pin to an upstream tag.

## Consequences

- Builds are reproducible: the same app source builds the same daemon.
- Bumping the daemon is a deliberate change: update `REV`, the benchmark baseline, the changelog and the third-party notices together. See [Contributing](../../CONTRIBUTING.md#bumping-the-daemon-pin).
- The fork must stay reachable, because every build clones it.
- The credit stays with the upstream author, and the About window says so.
