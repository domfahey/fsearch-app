import Foundation
import Testing

@testable import FSearchKit

/// Stands in for the daemon's byte comparison: an NFC query finds only NFC
/// names, an NFD query only NFD names (Mac apps write names in NFD).
final class ByteCompareBackend: SearchBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _queries: [[Unicode.Scalar]] = []
    /// Each query's scalars, since Swift's == can't tell NFC from NFD.
    var queries: [[Unicode.Scalar]] { lock.withLock { _queries } }

    func search(_ q: String, limit: Int) async throws -> SearchReply {
        lock.withLock { _queries.append(Array(q.unicodeScalars)) }
        let nfd = q.unicodeScalars.contains("\u{301}")
        let hits =
            nfd
            ? [hit("/r/Cafe\u{301}.txt", 10), hit("/r/both.txt", 8)]
            : [hit("/r/caf\u{e9}-nfc.txt", 20), hit("/r/both.txt", 5)]
        return SearchReply(tookUs: 3, hits: Array(hits.prefix(limit)))
    }
    private func hit(_ p: String, _ s: Int32) -> Hit { Hit(path: p, kind: "file", size: 0, mtime: 0, score: s) }
    func grep(q: String, pattern: String, mode: GrepMode) async throws -> GrepReply { throw DaemonError.disconnected }
    func status() async throws -> DaemonStatus { throw DaemonError.disconnected }
    func ping() async throws {}
}

@MainActor @Suite struct NormalizationTests {
    @Test func nonASCIIQueryAlsoSearchesItsNFDForm() async {
        let b = ByteCompareBackend()
        let m = SearchModel(names: b, content: ScriptedBackend())
        m.query = "caf\u{e9}"
        await m.refresh()
        #expect(b.queries == [Array("caf\u{e9}".unicodeScalars), Array("cafe\u{301}".unicodeScalars)])
        #expect(m.items.map(\.path) == ["/r/caf\u{e9}-nfc.txt", "/r/Cafe\u{301}.txt", "/r/both.txt"], "merged by score")
        guard case let .file(both) = m.items.last else { Issue.record("no hit"); return }
        #expect(both.score == 8, "a path found by both keeps its best score")
        #expect(m.lastTookUs == 6, "both searches' time")
    }

    @Test func nfdQueryAlsoSearchesItsNFCForm() async {
        let b = ByteCompareBackend()
        let m = SearchModel(names: b, content: ScriptedBackend())
        m.query = "cafe\u{301}"
        await m.refresh()
        #expect(b.queries.count == 2 && m.items.count == 3)
    }

    @Test func asciiQuerySearchesOnce() async {
        let b = ByteCompareBackend()
        let m = SearchModel(names: b, content: ScriptedBackend())
        m.query = "cafe"
        await m.refresh()
        #expect(b.queries.count == 1)
    }

    @Test func mergedHitsKeepTheLimit() async {
        let b = ByteCompareBackend()
        let m = SearchModel(names: b, content: ScriptedBackend())
        m.query = "caf\u{e9} limit:2"
        await m.refresh()
        #expect(m.items.map(\.path) == ["/r/caf\u{e9}-nfc.txt", "/r/Cafe\u{301}.txt"])
    }

    @Test func nonASCIIWithNoOtherFormSearchesOnce() async {
        let b = ByteCompareBackend()
        let m = SearchModel(names: b, content: ScriptedBackend())
        m.query = "日本"
        await m.refresh()
        #expect(b.queries.count == 1, "CJK has no decomposition")
    }
}

@Suite struct MergeHitsTests {
    func h(_ p: String, _ s: Int32) -> Hit { Hit(path: p, kind: "file", size: 0, mtime: 0, score: s) }

    @Test func equalScoresKeepTheDaemonOrder() {
        let m = SearchModel.merged([h("/b", 5), h("/a", 5), h("/c", 9), h("/a", 1)], limit: 50)
        #expect(m.map(\.path) == ["/c", "/b", "/a"])
        #expect(m.last?.score == 5)
    }

    @Test func nfcAndNfdPathsAreOneRow() {
        let m = SearchModel.merged([h("/caf\u{e9}", 3), h("/cafe\u{301}", 7)], limit: 50)
        #expect(m.count == 1 && m[0].score == 7)
    }

    @Test func limitZeroIsEmpty() {
        #expect(SearchModel.merged([h("/a", 1)], limit: 0).isEmpty)
    }
}
