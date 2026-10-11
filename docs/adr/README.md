# Architecture Decision Records

These records explain why FSearch for Mac is built the way it is. Each one states the context, the decision and what follows from it. They use a short form of the MADR template.

| ADR | Title | Status |
|---|---|---|
| [0001](0001-native-swiftui-over-tauri-electron.md) | Native SwiftUI over Tauri or Electron | Accepted |
| [0002](0002-bundle-the-fsearch-daemon-via-smappservice.md) | Bundle the fsearch daemon and run it with SMAppService | Accepted |
| [0003](0003-never-take-over-a-daemon-the-app-did-not-start.md) | Never take over a daemon the app did not start | Accepted |
| [0004](0004-two-socket-connections-and-latest-wins.md) | Two socket connections, and the latest search wins | Accepted |
| [0005](0005-tests-never-touch-the-real-index.md) | Tests never touch the real index | Accepted |
| [0006](0006-not-on-the-mac-app-store.md) | Not on the Mac App Store | Accepted |
| [0007](0007-test-seams-inert-test-host-and-test-mode.md) | Test seams, inert test host and test mode | Accepted |
| [0008](0008-strip-sparkles-xpc-services.md) | Strip Sparkle's XPC services (not sandboxed) | Accepted |
| [0009](0009-coverage-gates.md) | Coverage gates (FSearchKit 90%, app unit tests 80%) | Superseded in part by 0011 |
| [0010](0010-pin-the-daemon-to-a-fork-commit.md) | Pin the daemon to a fork commit until upstream merges | Accepted |
| [0011](0011-app-unit-test-gate-at-90.md) | App unit-test coverage gate at 90% | Accepted |

To add a record, copy the shape of an existing one, use the next number, and add a row here. Do not edit an accepted record to change its decision. Write a new one that supersedes it.

For the big picture, see [Architecture](../architecture.md). The original design is in the [design spec](../superpowers/specs/2026-10-10-fsearch-app-design.md).
