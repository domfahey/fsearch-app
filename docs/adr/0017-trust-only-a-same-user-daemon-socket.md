# 0017. Trust only a same-user daemon socket, and decide helper ownership from the socket holder

Date: 2026-10-10
Status: Accepted

## Context

The app sends search queries over a Unix socket in `~/Library/Application Support/FSearch`. Another process of the same user could plant a socket there, or a different daemon (a CLI install's) could hold it. The app also has to know whether the daemon is its own helper, because it restarts and removes only what it owns ([ADR 0003](0003-never-take-over-a-daemon-the-app-did-not-start.md)). Earlier checks used the login item's state, which says nothing about who answers.

## Considered options

- Trust any socket at the path. A planted socket would receive queries.
- Check the peer's uid, and name the holder by the pid in `socket.lock` plus its path and signature. This is the choice below.
- Also verify the peer's code signature on every connection. This is stricter, but slower and harder to test, and is left as a follow-up.

## Decision

- `LineSocket` calls `getpeereid` after `connect` and refuses a peer whose uid is not `expectedPeerUid`, which defaults to `getuid()` in `DaemonClient`. It never sends a query to that socket.
- `SocketHolder` reads the pid from `socket.lock` without locking it and classifies the holder as `none`, `ours` or `other`. It is `ours` when it is `<bundle>/Contents/Helpers/fsearch` (nothing else in the bundle counts), or a moved helper whose signature satisfies our identifier on an Apple-anchored certificate of our team. An unsigned `FSearch.app` helper counts only when the app itself is not team-signed (a dev or ad-hoc build).
- `DaemonManager.ownsDaemon` is true only when our login item is enabled and the holder is not `other`. A running CLI daemon is never restarted. Restarts are serialized and bounded, and the helper is restarted once after an app update, detected by its stored identity.

## Consequences

- A socket served by another user is ignored, and a CLI daemon is never taken over.
- Known limits: the pid in `socket.lock` is advisory, since the daemon writes it and a process of the same user could write another. The peer's code signature is not checked on the connection itself, which is a possible follow-up.
- The same change limited test hooks (`-FSEARCH_SOCKET`, `-UITestShowPanel`, XCTest variables) to Debug builds. See [ADR 0007](0007-test-seams-inert-test-host-and-test-mode.md).

## Amendment

2026-11-26: The app now also verifies the socket peer's code signature, the follow-up named above. On each new connection `LineSocket` reads the peer's audit token (`LOCAL_PEERTOKEN`), and `PeerIdentifier` checks that process's signature with the Security framework, using the same rules as `SocketHolder`. The audit token names the exact process that accepted the connection, so a pid written into `socket.lock` or a reused pid cannot fake it. This is done once per connection, on the control connection only, not per request. The result is `ours`, `other`, or `none` when the peer's file is gone and it is not signed as our helper. `DaemonPlan.holder` combines it with `socket.lock` and takes the more cautious answer, because the peer is named when the control connection last answered and another daemon may hold the socket since; when the token cannot be read, `socket.lock` alone decides. An unknown same-user daemon, such as the CLI's, is still used for searches, but is never taken for ours. The decision above stands. Index Details shows the result in its **Daemon** row.
