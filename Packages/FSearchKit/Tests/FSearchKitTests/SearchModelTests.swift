import Foundation
import Testing
@testable import FSearchKit

/// A backend whose answers can be delayed per query, to stage out-of-order replies.
final class ScriptedBackend: SearchBackend, @unchecked Sendable {
    var delays: [String: Double] = [:]
    var fail: DaemonError?
    func search(_ q: String, limit: Int) async throws -> SearchReply {
        try await Task.sleep(for: .milliseconds(Int((delays[q] ?? 0) * 1000)))
        if let fail { throw fail }
        return SearchReply(tookUs: 9, hits: [Hit(path: "/r/\(q)", kind: "file", size: 0, mtime: 0, score: 0)])
    }
    func grep(q: String, pattern: String, mode: GrepMode) async throws -> GrepReply {
        if let fail { throw fail }
        let json = #"{"ok":true,"took_us":50,"source":"index","candidates":1,"read":1,"complete":true,"files":[{"path":"/r/f.txt","matches":[{"line":3,"text":"\#(pattern)|\#(q)|\#(mode.rawValue)"}]}]}"#
        return try decodeReply(Data(json.utf8), as: GrepReply.self)
    }
    func status() async throws -> DaemonStatus { throw DaemonError.disconnected }
    func ping() async throws {}
}

/// A name search for `hangingQuery` never answers unless cancelled; it records
/// that it started and that it was cancelled. Other queries answer at once.
final class HangingBackend: SearchBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _started = false, _cancelled = false
    private let hangingQuery: String
    init(hangingQuery: String) { self.hangingQuery = hangingQuery }
    var started: Bool { lock.withLock { _started } }
    var cancelled: Bool { lock.withLock { _cancelled } }

    func search(_ q: String, limit: Int) async throws -> SearchReply {
        guard q == hangingQuery else {
            return SearchReply(tookUs: 9, hits: [Hit(path: "/r/\(q)", kind: "file", size: 0, mtime: 0, score: 0)])
        }
        lock.withLock { _started = true }
        do { try await Task.sleep(for: .seconds(10)) }
        catch {
            lock.withLock { _cancelled = true }
            throw error
        }
        return SearchReply(tookUs: 9, hits: [])
    }
    func grep(q: String, pattern: String, mode: GrepMode) async throws -> GrepReply { throw DaemonError.disconnected }
    func status() async throws -> DaemonStatus { throw DaemonError.disconnected }
    func ping() async throws {}
}

/// A name search for `slowQuery` that ignores cancellation: it sleeps in a
/// detached task, so the reply still arrives after the caller has moved on.
final class IgnoringCancelBackend: SearchBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _started = false
    var started: Bool { lock.withLock { _started } }

    func search(_ q: String, limit: Int) async throws -> SearchReply {
        if q == "old" {
            lock.withLock { _started = true }
            await Task.detached { try? await Task.sleep(for: .milliseconds(300)) }.value
        }
        return SearchReply(tookUs: 9, hits: [Hit(path: "/r/\(q)", kind: "file", size: 0, mtime: 0, score: 0)])
    }
    func grep(q: String, pattern: String, mode: GrepMode) async throws -> GrepReply { throw DaemonError.disconnected }
    func status() async throws -> DaemonStatus { throw DaemonError.disconnected }
    func ping() async throws {}
}

/// A backend that reports when its slow query has begun.
protocol StartSignal: Sendable { var started: Bool { get } }
extension HangingBackend: StartSignal {}
extension IgnoringCancelBackend: StartSignal {}

/// Waits (bounded) until a backend has begun answering its slow query.
private func waitUntilStarted(_ b: some StartSignal) async throws {
    for _ in 0..<400 where !b.started { try await Task.sleep(for: .milliseconds(5)) }
}

@MainActor @Suite struct SearchModelTests {
    @Test func namesSearch() async {
        let m = SearchModel(names: ScriptedBackend(), content: ScriptedBackend())
        m.query = "main.rs"
        await m.refresh()
        #expect(m.items == [.file(Hit(path: "/r/main.rs", kind: "file", size: 0, mtime: 0, score: 0))])
        #expect(m.phase == .results && m.lastTookUs == 9)
    }

    @Test func latestWins() async {
        let b = ScriptedBackend()
        b.delays = ["m": 0.3, "ma": 0.2, "mai": 0.1, "main": 0]
        let m = SearchModel(names: b, content: ScriptedBackend())
        await withTaskGroup(of: Void.self) { g in
            for q in ["m", "ma", "mai", "main"] {
                m.query = q
                g.addTask { await m.refresh() }
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
        #expect(m.items.map(\.path) == ["/r/main"], "slower answers to older queries are dropped")
    }

    @Test func contentModeSplitsFilters() async {
        let m = SearchModel(names: ScriptedBackend(), content: ScriptedBackend())
        m.mode = .content
        m.query = "hello world ext:rs"
        await m.refresh()
        guard case let .line(path, match) = m.items.first else { Issue.record("no line result"); return }
        #expect(path == "/r/f.txt" && match.line == 3)
        #expect(match.text == "hello world|ext:rs|literal")
    }

    @Test func symbolsModeUsesSymbolGrep() async {
        let m = SearchModel(names: ScriptedBackend(), content: ScriptedBackend())
        m.mode = .symbols
        m.query = "apply_dir"
        await m.refresh()
        guard case let .line(_, match) = m.items.first else { Issue.record("no line result"); return }
        #expect(match.text.hasSuffix("|symbol"))
    }

    @Test func emptyQueryIsIdle() async {
        let m = SearchModel(names: ScriptedBackend(), content: ScriptedBackend())
        m.query = "  "
        await m.refresh()
        #expect(m.phase == .idle && m.items.isEmpty)
    }

    @Test func indexingIsItsOwnPhase() async {
        let b = ScriptedBackend()
        b.fail = .indexing("indexing (first run scans the whole disk, ~20s)")
        let m = SearchModel(names: b, content: ScriptedBackend())
        m.query = "x"
        await m.refresh()
        #expect(m.phase == .indexing)
    }

    @Test func errorsAreKeptAndResultsCleared() async {
        let b = ScriptedBackend()
        b.fail = .daemon("unknown type dir")
        let m = SearchModel(names: b, content: ScriptedBackend())
        m.query = "type:dir x"
        await m.refresh()
        #expect(m.phase == .failed(.daemon("unknown type dir")) && m.items.isEmpty)
    }

    @Test func everySearchIsReported() async {
        let m = SearchModel(names: ScriptedBackend(), content: ScriptedBackend())
        var log: [SearchModel.LogEntry] = []
        m.onSearched = { log.append($0) }
        m.query = "abc"
        await m.refresh()
        #expect(log.count == 1 && log[0].query == "abc" && log[0].mode == .names && log[0].resultCount == 1 && log[0].tookUs == 9)
    }

    @Test func supersededSearchIsCancelled() async throws {
        let b = HangingBackend(hangingQuery: "slow")
        let m = SearchModel(names: b, content: ScriptedBackend())
        var log: [SearchModel.LogEntry] = []
        m.onSearched = { log.append($0) }
        let t0 = Date()
        m.query = "slow"
        let first = Task { await m.refresh() }
        try await waitUntilStarted(b)
        #expect(b.started, "the hanging search reached the backend")
        m.query = "fast"
        await m.refresh()
        await first.value
        #expect(b.cancelled, "the superseded call was cancelled")
        #expect(Date().timeIntervalSince(t0) < 2, "a hung daemon costs no timeout")
        #expect(m.items.map(\.path) == ["/r/fast"] && m.phase == .results)
        #expect(log.map(\.query) == ["fast"], "only the newest search is reported")
    }

    @Test func emptyQueryCancelsInFlight() async throws {
        let b = HangingBackend(hangingQuery: "slow")
        let m = SearchModel(names: b, content: ScriptedBackend())
        m.query = "slow"
        let first = Task { await m.refresh() }
        try await waitUntilStarted(b)
        m.query = ""
        await m.refresh()
        await first.value
        #expect(b.cancelled, "clearing the query cancels the search in flight")
        #expect(m.phase == .idle && m.items.isEmpty)
    }

    @Test func staleReplyIsDropped() async throws {
        let b = IgnoringCancelBackend()
        let m = SearchModel(names: b, content: ScriptedBackend())
        var log: [SearchModel.LogEntry] = []
        m.onSearched = { log.append($0) }
        m.query = "old"
        let first = Task { await m.refresh() }
        try await waitUntilStarted(b)
        m.query = "new"
        await m.refresh()
        await first.value
        #expect(m.items.map(\.path) == ["/r/new"] && m.phase == .results)
        #expect(log.map(\.query) == ["new"], "the late reply to the old query is not reported")
    }
}
