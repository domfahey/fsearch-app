import Foundation
import Testing

@testable import FSearchKit

@Suite struct DaemonClientTests {
    @Test func searchRoundTrip() async throws {
        let d = FakeDaemon { req in
            ["ok": true, "took_us": 5, "hits": [["path": "/x/\(req["q"]!)", "kind": "file", "size": 1, "mtime": 2, "score": 3]]]
        }
        let c = DaemonClient(socketPath: d.path)
        let r = try await c.search("main.rs", limit: 50)
        #expect(r.hits.first?.path == "/x/main.rs")
        #expect(d.requests.first?["limit"] as? Int == 50)
    }

    @Test func requestsAreAnsweredInOrderOnOneConnection() async throws {
        let d = FakeDaemon { req in
            ["ok": true, "took_us": 1, "hits": [["path": "\(req["q"]!)", "kind": "file", "size": 0, "mtime": 0, "score": 0]]]
        }
        let c = DaemonClient(socketPath: d.path)
        let results = try await withThrowingTaskGroup(of: (String, String).self) { g in
            for q in ["a", "b", "c", "d", "e"] { g.addTask { (q, try await c.search(q, limit: 1).hits[0].path) } }
            return try await g.reduce(into: [String: String]()) { $0[$1.0] = $1.1 }
        }
        #expect(results == ["a": "a", "b": "b", "c": "c", "d": "d", "e": "e"], "each caller gets its own answer")
        #expect(d.accepted == 1, "all five requests share one connection")
    }

    @Test func noDaemonIsDisconnected() async {
        let c = DaemonClient(socketPath: NSTemporaryDirectory() + "nothing-here.sock")
        let t0 = Date()
        await #expect(throws: DaemonError.disconnected) { try await c.ping() }
        #expect(Date().timeIntervalSince(t0) < 1.0)
    }

    /// A socket served by another user is never trusted: no request is sent.
    @Test func aPeerOfAnotherUserIsRefused() async throws {
        let d = FakeDaemon { _ in ["ok": true] }
        defer { d.stop() }
        let stranger = DaemonClient(socketPath: d.path, expectedPeerUid: getuid() &+ 1)
        await #expect(throws: DaemonError.disconnected) { try await stranger.ping() }
        #expect(d.requests.isEmpty)
        try await DaemonClient(socketPath: d.path).ping()
        #expect(d.requests.count == 1)
    }

    @Test func peerCheckIsBySameUid() {
        #expect(peerIsTrusted(peerUid: 501, expected: 501))
        #expect(!peerIsTrusted(peerUid: 0, expected: 501))
        #expect(!peerIsTrusted(peerUid: nil, expected: 501))
    }

    @Test func hungDaemonTimesOut() async {
        let d = FakeDaemon { _ in nil }
        let c = DaemonClient(socketPath: d.path, timeout: 0.3)
        let t = Date()
        await #expect(throws: DaemonError.timeout) { try await c.ping() }
        #expect(Date().timeIntervalSince(t) < 2)
    }

    @Test func reconnectsAfterTheDaemonComesBack() async throws {
        let first = FakeDaemon { _ in ["ok": true] }
        let c = DaemonClient(socketPath: first.path)
        try await c.ping()
        first.stop()
        // A new daemon on the same path. The very next ping retries once on a fresh connection.
        let second = FakeDaemon(path: first.path) { _ in ["ok": true] }
        try await c.ping()
        _ = second
    }

    @Test func stoppingAnOldDaemonLeavesTheNewOneAlone() async throws {
        // Repeated: a stopped daemon's accept thread once used a listener fd number that the
        // next daemon's socket() had reused, and dropped the new daemon's connection. Stopping
        // right after start (before that thread runs) is the window, so hit it many times.
        for _ in 0..<50 {
            let first = FakeDaemon { _ in ["ok": true] }
            first.stop()
            let second = FakeDaemon(path: first.path) { _ in ["ok": true] }
            first.stop()  // a second stop on a stopped daemon is a no-op
            try await DaemonClient(socketPath: second.path).ping()
            second.stop()
        }
    }

    @Test func aLateReplyNeverReachesTheNextCaller() async throws {
        // "a" answers after the client has given up. LineSocket must drop that connection on
        // timeout, or "b" would read "a"'s stale reply off the same socket.
        let d = FakeDaemon { req in
            let q = req["q"] as? String ?? ""
            if q == "a" { Thread.sleep(forTimeInterval: 0.6) }
            return ["ok": true, "took_us": 1, "hits": [["path": "/r/\(q)", "kind": "file", "size": 0, "mtime": 0, "score": 0]]]
        }
        let c = DaemonClient(socketPath: d.path, timeout: 0.3)
        await #expect(throws: DaemonError.timeout) { try await c.search("a", limit: 1) }
        try await Task.sleep(for: .milliseconds(500))  // let the late "a" reply be written
        let r = try await c.search("b", limit: 1)
        #expect(r.hits.first?.path == "/r/b")
        #expect(d.accepted == 2, "the timed-out connection was replaced")
    }

    @Test func timeoutIsNotRetried() async {
        // Reply to the first request only; the second hangs.
        let d = FakeDaemon { req in (req["id"] as? Int) == 1 ? ["ok": true] : nil }
        let c = DaemonClient(socketPath: d.path, timeout: 0.3)
        try? await c.ping()
        await #expect(throws: DaemonError.timeout) { try await c.ping() }
        #expect(d.requests.count == 2, "a timed-out request is not resent")
    }

    @Test func cancelledQueuedCallsNeverHitTheSocket() async {
        let d = FakeDaemon { _ in nil }
        let c = DaemonClient(socketPath: d.path, timeout: 0.3)
        let t0 = Date()
        let tasks = (0..<5).map { _ in Task { try await c.ping() } }
        for t in tasks.prefix(4) { t.cancel() }
        await #expect(throws: DaemonError.timeout) { try await tasks[4].value }
        // Loose bound: the request count below is the real check; this only catches
        // the cancelled calls each waiting out their own timeout (5 x 0.3 s).
        #expect(Date().timeIntervalSince(t0) < 5.0)
        #expect(d.requests.count <= 2, "the cancelled calls were skipped, not sent")
    }

    @Test func cancelledCallThrowsCancellationError() async {
        let d = FakeDaemon { _ in nil }
        let c = DaemonClient(socketPath: d.path, timeout: 0.3)
        let blocker = Task { try? await c.ping() }
        let victim = Task { try await c.ping() }
        victim.cancel()
        await #expect(throws: CancellationError.self) { try await victim.value }
        _ = await blocker.value
    }

    @Test func saveSendsTheSaveOp() async throws {
        let d = FakeDaemon { _ in ["ok": true, "scheduled": true] }
        try await DaemonClient(socketPath: d.path).save()
        #expect(d.requests.first?["op"] as? String == "save")
    }

    @Test func daemonErrorsSurface() async {
        let d = FakeDaemon { _ in ["ok": false, "error": "regex parse error"] }
        let c = DaemonClient(socketPath: d.path)
        await #expect(throws: DaemonError.daemon("regex parse error")) {
            try await c.grep(q: "", pattern: "(", mode: .regex)
        }
    }

    // MARK: reply ids

    @Test func aLeftoverReplyNeverReachesTheNextRequest() async throws {
        // Request 1 gets its reply plus an extra line with id 1; request 2 must not see that extra.
        let srv = RawServer { fd, _ in
            var n = 0
            while RawServer.readLine(fd) {
                n += 1
                if n == 1 {
                    RawServer.send(
                        fd, #"{"ok":true,"took_us":1,"hits":[{"path":"/one","kind":"file","size":0,"mtime":0,"score":0}],"id":1}"# + "\n")
                    RawServer.send(
                        fd, #"{"ok":true,"took_us":1,"hits":[{"path":"/extra","kind":"file","size":0,"mtime":0,"score":0}],"id":1}"# + "\n")
                } else {
                    RawServer.send(
                        fd, #"{"ok":true,"took_us":1,"hits":[{"path":"/two","kind":"file","size":0,"mtime":0,"score":0}],"id":2}"# + "\n")
                }
            }
            close(fd)
        }
        defer { srv.stop() }
        let c = DaemonClient(socketPath: srv.path, timeout: 1)
        #expect(try await c.search("a", limit: 1).hits.first?.path == "/one")
        #expect(try await c.search("b", limit: 1).hits.first?.path == "/two")
        #expect(srv.accepted == 1)
    }

    @Test func aStaleLineAheadOfTheRealReplyIsDiscarded() async throws {
        let srv = RawServer { fd, _ in
            var id = 0
            while RawServer.readLine(fd) {
                id += 1
                RawServer.send(
                    fd, #"{"ok":true,"took_us":1,"hits":[{"path":"/stale","kind":"file","size":0,"mtime":0,"score":0}],"id":0}"# + "\n")
                RawServer.send(
                    fd,
                    #"{"ok":true,"took_us":1,"hits":[{"path":"/real\#(id)","kind":"file","size":0,"mtime":0,"score":0}],"id":\#(id)}"#
                        + "\n")
            }
            close(fd)
        }
        defer { srv.stop() }
        let c = DaemonClient(socketPath: srv.path, timeout: 1)
        #expect(try await c.search("a", limit: 1).hits.first?.path == "/real1")
        #expect(try await c.search("b", limit: 1).hits.first?.path == "/real2")
    }

    @Test func onlyMismatchedRepliesTimeOutAndFreshenTheConnection() async throws {
        let srv = RawServer { fd, _ in
            while RawServer.readLine(fd) {
                RawServer.send(fd, #"{"ok":true,"id":777}"# + "\n")
            }
            close(fd)
        }
        defer { srv.stop() }
        let c = DaemonClient(socketPath: srv.path, timeout: 0.3)
        await #expect(throws: DaemonError.timeout) { try await c.ping() }
        await #expect(throws: DaemonError.timeout) { try await c.ping() }
        #expect(srv.accepted == 2, "the connection was closed after the timeout")
    }

    @Test func aChattyDaemonCannotHoldACallPastItsDeadline() async throws {
        // Mismatched lines keep arriving faster than the per-read timeout; the call still ends.
        let srv = RawServer { fd, _ in
            _ = RawServer.readLine(fd)
            for _ in 0..<40 {
                RawServer.send(fd, #"{"ok":true,"id":777}"# + "\n")
                Thread.sleep(forTimeInterval: 0.05)
            }
            close(fd)
        }
        defer { srv.stop() }
        let c = DaemonClient(socketPath: srv.path, timeout: 0.4)
        let t0 = Date()
        await #expect(throws: DaemonError.timeout) { try await c.ping() }
        #expect(Date().timeIntervalSince(t0) < 1.2)
    }

    @Test func repliesWithoutAnIdAreAccepted() async throws {
        let srv = RawServer { fd, _ in
            while RawServer.readLine(fd) { RawServer.send(fd, #"{"ok":true}"# + "\n") }
            close(fd)
        }
        defer { srv.stop() }
        try await DaemonClient(socketPath: srv.path, timeout: 1).ping()
    }
}
