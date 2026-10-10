import Foundation
import Observation

public enum SearchMode: Equatable, Sendable { case names, content, symbols }

public enum ResultItem: Equatable, Identifiable, Sendable {
    case file(Hit)
    case line(path: String, match: Match)

    public var path: String {
        switch self { case let .file(h): h.path; case let .line(p, _): p }
    }
    public var id: String {
        switch self { case let .file(h): h.path; case let .line(p, m): "\(p):\(m.line)" }
    }
}

public enum SearchPhase: Equatable, Sendable { case idle, loading, results, indexing, failed(DaemonError) }

/// One search box. Each refresh is a generation; only the newest one may
/// publish, so slow answers to older queries are dropped.
@MainActor @Observable
public final class SearchModel {
    public struct LogEntry: Equatable, Sendable {
        public let query: String
        public let mode: SearchMode
        public let resultCount: Int
        public let tookUs: UInt64?
        public let roundTripMs: Double
        public let error: String?
    }

    public var query = ""
    public var mode: SearchMode = .names
    public private(set) var items: [ResultItem] = []
    public private(set) var phase: SearchPhase = .idle
    public private(set) var lastTookUs: UInt64?
    @ObservationIgnored public var onSearched: ((LogEntry) -> Void)?
    /// Called with the new phase every time a search finishes (results,
    /// indexing or failed), even when the phase is the same as before: a
    /// second dropped connection must be seen as one, which watching the
    /// phase for changes can miss.
    @ObservationIgnored public var onSettled: ((SearchPhase) -> Void)?

    @ObservationIgnored private let names: SearchBackend
    @ObservationIgnored private let content: SearchBackend
    @ObservationIgnored private var generation = 0
    /// The backend call of the newest refresh; a newer refresh cancels it, so a
    /// hung daemon costs one timeout, not one per keystroke.
    @ObservationIgnored private var inflight: Task<([ResultItem], UInt64), Error>?

    public init(names: SearchBackend, content: SearchBackend) {
        self.names = names
        self.content = content
    }

    public func refresh() async {
        // A filter still being typed (`foo size:`) is not a query yet: keep
        // what is showing, and let any search already under way finish.
        if QuerySplit.endsInHalfTypedFilter(query) { return }
        generation += 1
        inflight?.cancel()
        inflight = nil
        let gen = generation, q = query, mode = self.mode
        // Nothing to send: a blank query, the "?" cheat sheet, or a content
        // query made only of filters, or a name query whose grep:/sym: has no
        // value yet (an empty pattern matches every line).
        if Self.isBlank(q) || QuerySyntax.isCheatSheet(q) || Self.emptyPattern(q, mode) {
            (items, phase, lastTookUs) = ([], .idle, nil)
            return
        }
        phase = .loading
        let started = Date()
        let task = Task { try await self.run(q, mode) }
        inflight = task
        do {
            let (found, took) = try await task.value
            guard gen == generation else { return }
            (items, phase, lastTookUs) = (found, .results, took)
            report(q, mode, found.count, took, started, nil)
        } catch is CancellationError {
            // Superseded by a newer refresh (or the caller went away): no state change.
            return
        } catch let e as DaemonError {
            guard gen == generation else { return }
            (items, lastTookUs) = ([], nil)
            if case .indexing = e { phase = .indexing } else { phase = .failed(e) }
            report(q, mode, 0, nil, started, String(describing: e))
        } catch {
            guard gen == generation else { return }
            (items, phase, lastTookUs) = ([], .failed(.badReply(String(describing: error))), nil)
            report(q, mode, 0, nil, started, String(describing: error))
        }
    }

    private static func emptyPattern(_ q: String, _ mode: SearchMode) -> Bool {
        mode == .names ? QuerySplit.contentSearch(q)?.pattern.isEmpty == true : QuerySplit.split(q).pattern.isEmpty
    }

    /// A query with nothing but spaces searches nothing.
    public nonisolated static func isBlank(_ q: String) -> Bool {
        q.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func run(_ q: String, _ mode: SearchMode) async throws -> ([ResultItem], UInt64) {
        switch mode {
        case .names:
            // grep:/regex:/sym: make the daemon answer with lines: run it as the content search it is.
            if let c = QuerySplit.contentSearch(q) {
                let r = try await content.grep(q: c.q, pattern: c.pattern, mode: c.mode)
                return (lines(r), r.tookUs)
            }
            let r = try await names.search(q, limit: 50)
            return (r.hits.map(ResultItem.file), r.tookUs)
        case .content, .symbols:
            let (pattern, filters) = QuerySplit.split(q)
            let r = try await content.grep(q: filters, pattern: pattern, mode: mode == .symbols ? .symbol : .literal)
            return (lines(r), r.tookUs)
        }
    }

    private func lines(_ r: GrepReply) -> [ResultItem] {
        r.files.flatMap { f in f.matches.map { ResultItem.line(path: f.path, match: $0) } }
    }

    private func report(_ q: String, _ mode: SearchMode, _ n: Int, _ took: UInt64?, _ started: Date, _ err: String?) {
        onSearched?(LogEntry(query: q, mode: mode, resultCount: n, tookUs: took, roundTripMs: Date().timeIntervalSince(started) * 1000, error: err))
        onSettled?(phase)
    }
}
