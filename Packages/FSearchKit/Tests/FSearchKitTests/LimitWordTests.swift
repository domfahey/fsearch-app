import Foundation
import Testing

@testable import FSearchKit

/// `limit:` in a name query: the daemon applies JSON fields after `q`, so a
/// JSON `limit` would always override the typed one.
@Suite struct LimitWordTests {
    func obj(_ d: Data) -> [String: Any] { try! JSONSerialization.jsonObject(with: d) as! [String: Any] }

    @Test(arguments: ["main limit:200", "limit:5 main", #""limit:7" x"#, "a limit:x"])
    func limitWordLeavesOutTheJSONLimit(_ q: String) {
        let o = obj(Request.search(q: q, limit: 50).json(id: 1))
        #expect(o["limit"] == nil && o["q"] as? String == q)
    }

    @Test(arguments: ["main", "unlimited", "LIMIT:5", "xlimit:5"])
    func noLimitWordKeepsTheJSONLimit(_ q: String) {
        #expect(obj(Request.search(q: q, limit: 50).json(id: 1))["limit"] as? Int == 50)
    }

    @Test func typedLimitValue() {
        #expect(QuerySplit.limit("main limit:200") == 200)
        #expect(QuerySplit.limit("limit:3 limit:9") == 9, "the last one wins, as in the daemon")
        #expect(QuerySplit.limit("main") == nil)
        #expect(QuerySplit.limit("limit:x") == nil)
    }

    @Test func daemonReceivesNoLimitField() async throws {
        let d = FakeDaemon { _ in ["ok": true, "took_us": 5, "hits": []] }
        defer { d.stop() }
        let c = DaemonClient(socketPath: d.path)
        _ = try await c.search("main limit:200", limit: 50)
        #expect(d.requests.first?["limit"] == nil)
        #expect(d.requests.first?["q"] as? String == "main limit:200")
    }
}

/// Answers every name search with `count` hits.
final class ManyHitsBackend: SearchBackend, @unchecked Sendable {
    let count: Int
    init(count: Int) { self.count = count }
    func search(_ q: String, limit: Int) async throws -> SearchReply {
        SearchReply(tookUs: 1, hits: (0..<count).map { Hit(path: "/r/\($0)", kind: "file", size: 0, mtime: 0, score: 0) })
    }
    func grep(q: String, pattern: String, mode: GrepMode) async throws -> GrepReply { throw DaemonError.disconnected }
    func status() async throws -> DaemonStatus { throw DaemonError.disconnected }
    func ping() async throws {}
}

@MainActor @Suite struct ShownLimitTests {
    @Test func aHugeLimitIsCappedInThePanel() async {
        let m = SearchModel(names: ManyHitsBackend(count: SearchModel.shownLimit + 500), content: ScriptedBackend())
        m.query = "a limit:100000"
        await m.refresh()
        #expect(m.items.count == SearchModel.shownLimit)
        #expect(m.items.first?.path == "/r/0", "the best hits are kept")
    }

    @Test func smallAnswersAreUntouched() async {
        let m = SearchModel(names: ManyHitsBackend(count: 7), content: ScriptedBackend())
        m.query = "a"
        await m.refresh()
        #expect(m.items.count == 7)
    }
}
