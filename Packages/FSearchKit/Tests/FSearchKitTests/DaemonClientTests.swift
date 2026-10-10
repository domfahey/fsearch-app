import Foundation
import Testing
@testable import FSearchKit

@Suite struct DaemonClientTests {
    @Test func searchRoundTrip() async throws {
        let d = FakeDaemon { req in ["ok": true, "took_us": 5, "hits": [["path": "/x/\(req["q"]!)", "kind": "file", "size": 1, "mtime": 2, "score": 3]]] }
        let c = DaemonClient(socketPath: d.path)
        let r = try await c.search("main.rs", limit: 50)
        #expect(r.hits.first?.path == "/x/main.rs")
        #expect(d.requests.first?["limit"] as? Int == 50)
    }

    @Test func requestsAreAnsweredInOrderOnOneConnection() async throws {
        let d = FakeDaemon { req in ["ok": true, "took_us": 1, "hits": [["path": "\(req["q"]!)", "kind": "file", "size": 0, "mtime": 0, "score": 0]]] }
        let c = DaemonClient(socketPath: d.path)
        let results = try await withThrowingTaskGroup(of: (String, String).self) { g in
            for q in ["a", "b", "c", "d", "e"] { g.addTask { (q, try await c.search(q, limit: 1).hits[0].path) } }
            return try await g.reduce(into: [String: String]()) { $0[$1.0] = $1.1 }
        }
        #expect(results == ["a": "a", "b": "b", "c": "c", "d": "d", "e": "e"], "each caller gets its own answer")
    }

    @Test func noDaemonIsDisconnected() async {
        let c = DaemonClient(socketPath: NSTemporaryDirectory() + "nothing-here.sock")
        await #expect(throws: DaemonError.disconnected) { try await c.ping() }
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
        await #expect(throws: DaemonError.self) { try await c.ping() }
        // A new daemon on the same path.
        let second = FakeDaemon(path: first.path) { _ in ["ok": true] }
        try await c.ping()
        _ = second
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
}
