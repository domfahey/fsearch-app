# 0004. Two socket connections, and the latest search wins

Date: 2026-10-10
Status: Accepted

## Context

The app searches on every keystroke, with no delay. A name search takes a few milliseconds. A content search can take up to its time budget of 250 ms.

The daemon answers each connection in order. If name and content searches shared a connection, a slow content search would hold back the name results for the next keystroke. Also, answers can arrive after you have typed more, and must not replace newer results.

## Decision

- Use two connections to the daemon. One carries name searches. The other carries content and definition searches. Each connection sends one request at a time, so replies never cross.
- Give each refresh a generation number. Only the newest refresh may publish results. Starting a new one cancels the old one, so a hung daemon costs one timeout, not one per keystroke.
- A cancelled request that is still queued is skipped without touching the socket.

## Consequences

- Typing stays fast even while a content search runs.
- Stale answers are dropped. The list never shows results for an older query.
- The panel shows "Starting search…" if the daemon does not answer, and recovers by itself when it does.
- There is a little more state to manage. The key logic is a pure function of state and key, so it can be tested without any UI.
