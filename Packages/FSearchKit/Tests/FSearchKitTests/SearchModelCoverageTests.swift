import Foundation
import Testing
@testable import FSearchKit

/// A name search for "old" parks until `release()`, ignoring cancellation, then
/// fails with `error`. Everything else answers at once. Deterministic: no timing.
final class GatedFailBackend: SearchBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var cont: CheckedContinuation<Void, Never>?
    private var _parked = false
    private var released = false
    let error: Error
    init(error: Error) { self.error = error }
    var parked: Bool { lock.withLock { _parked } }

    func release() {
        let c = lock.withLock { () -> CheckedContinuation<Void, Never>? in released = true; defer { cont = nil }; return cont }
        c?.resume()
    }

    func search(_ q: String, limit: Int) async throws -> SearchReply {
        guard q == "old" else { return SearchReply(tookUs: 1, hits: [Hit(path: "/r/\(q)", kind: "file", size: 0, mtime: 0, score: 0)]) }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let resumeNow = lock.withLock { () -> Bool in
                _parked = true
                if released { return true }
                cont = c
                return false
            }
            if resumeNow { c.resume() }
        }
        throw error
    }
    func grep(q: String, pattern: String, mode: GrepMode) async throws -> GrepReply { throw error }
    func status() async throws -> DaemonStatus { throw DaemonError.disconnected }
    func ping() async throws {}
}

/// Every call fails with `error`.
struct FailingBackend: SearchBackend {
    let error: Error
    func search(_ q: String, limit: Int) async throws -> SearchReply { throw error }
    func grep(q: String, pattern: String, mode: GrepMode) async throws -> GrepReply { throw error }
    func status() async throws -> DaemonStatus { throw error }
    func ping() async throws { throw error }
}

@MainActor @Suite struct SearchModelCoverageTests {
    func waitParked(_ b: GatedFailBackend) async throws {
        for _ in 0..<2000 where !b.parked { try await Task.sleep(for: .milliseconds(5)) }
        #expect(b.parked)
    }

    /// A failure that lands after a newer search has published, whichever catch
    /// clause it goes through, changes nothing and is not logged.
    @Test(arguments: [
        DaemonError.daemon("old failed") as any Error,
        DaemonError.indexing("indexing"),
        CocoaError(.fileReadUnknown),
    ])
    func lateErrorFromASupersededSearchIsDropped(_ error: any Error) async throws {
        let b = GatedFailBackend(error: error)
        let m = SearchModel(names: b, content: FailingBackend(error: DaemonError.disconnected))
        var log: [SearchModel.LogEntry] = []
        m.onSearched = { log.append($0) }
        m.query = "old"
        let first = Task { await m.refresh() }
        try await waitParked(b)
        m.query = "new"
        await m.refresh()
        b.release()
        await first.value
        #expect(m.phase == .results && m.items.map(\.path) == ["/r/new"])
        #expect(log.map(\.query) == ["new"], "the stale failure is neither shown nor logged")
    }

    @Test func currentFailureAfterGoodResultsClearsItems() async {
        let m = SearchModel(names: RecordingBackend(), content: FailingBackend(error: DaemonError.timeout))
        m.query = "needle"
        await m.refresh()
        #expect(!m.items.isEmpty && m.lastTookUs != nil, "results to clear")
        m.mode = .content
        await m.refresh()
        #expect(m.phase == .failed(.timeout) && m.items.isEmpty)
        #expect(m.lastTookUs == nil, "no timing left over from the previous search")
    }

    @Test func failedSearchIsLoggedWithTheError() async {
        let m = SearchModel(names: FailingBackend(error: DaemonError.daemon("bad regex")), content: RecordingBackend())
        var log: [SearchModel.LogEntry] = []
        m.onSearched = { log.append($0) }
        m.query = "x"
        await m.refresh()
        #expect(log.count == 1)
        #expect(log[0].error == "bad regex")
        #expect(log[0].resultCount == 0 && log[0].tookUs == nil && log[0].mode == .names && log[0].roundTripMs >= 0)
    }

    @Test func indexingIsLoggedAndClearsPriorResults() async {
        let b = ScriptedBackend()
        let m = SearchModel(names: b, content: RecordingBackend())
        var log: [SearchModel.LogEntry] = []
        m.onSearched = { log.append($0) }
        m.query = "x"
        await m.refresh()
        #expect(!m.items.isEmpty && m.lastTookUs != nil, "results to clear")
        b.fail = .indexing("indexing")
        await m.refresh()
        #expect(m.phase == .indexing && m.items.isEmpty && m.lastTookUs == nil)
        #expect(log.last?.error == "The search index is still being built")
    }

    @Test func successThenBlankResetsEverything() async {
        let m = SearchModel(names: ScriptedBackend(), content: ScriptedBackend())
        m.query = "abc"
        await m.refresh()
        #expect(m.phase == .results && m.lastTookUs == 9)
        m.query = "   "
        await m.refresh()
        #expect(m.phase == .idle && m.items.isEmpty && m.lastTookUs == nil)
    }

    @Test func resultItemAccessors() {
        let hit = Hit(path: "/a/b", kind: "file", size: 1, mtime: 2, score: 3)
        #expect(ResultItem.file(hit).path == "/a/b" && ResultItem.file(hit).id == "/a/b")
        let l = ResultItem.line(path: "/a/b", match: Match(line: 4, text: "t"))
        #expect(l.path == "/a/b" && l.id == "/a/b:4")
        #expect(l != ResultItem.line(path: "/a/b", match: Match(line: 5, text: "t")))
    }

    @Test func isBlankOnlyCountsSpacesAndTabs() {
        #expect(SearchModel.isBlank("") && SearchModel.isBlank("  \t "))
        #expect(!SearchModel.isBlank(" a "))
        #expect(!SearchModel.isBlank("\n"), "a newline is not a space or a tab")
    }
}
