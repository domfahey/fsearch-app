import Foundation
import Observation

/// What the search box searches.
public enum SearchMode: Equatable, Sendable {
    /// File names (the default).
    case names
    /// Text inside files.
    case content
    /// Symbol definitions in code.
    case symbols
}

/// One result row: a file or a matching line.
public enum ResultItem: Equatable, Identifiable, Sendable {
    /// A file found by name.
    case file(Hit)
    /// A line found inside a file.
    case line(path: String, match: Match)

    /// The file the item is in.
    public var path: String {
        switch self {
        case let .file(h): h.path;
        case let .line(p, _): p
        }
    }
    /// Unique within one result list: the path, plus the line number for lines.
    public var id: String {
        switch self {
        case let .file(h): h.path;
        case let .line(p, m): "\(p):\(m.line)"
        }
    }
}

/// Where a search is, for the panel to render.
public enum SearchPhase: Equatable, Sendable {
    /// Nothing to search for.
    case idle
    /// A request is in flight.
    case loading
    /// Results (possibly none) are showing.
    case results
    /// The daemon is still building its first index.
    case indexing
    /// The search failed.
    case failed(DaemonError)
}

/// One search box. Each refresh is a generation; only the newest one may
/// publish, so slow answers to older queries are dropped.
///
/// - A newer ``refresh()`` cancels the older one's backend call; the older call returns
///   without changing state or calling the callbacks.
/// - ``onSearched`` and ``onSettled`` fire once for each search that finished as the newest
///   generation, never for a cancelled or superseded one.
/// - All state is main-actor isolated; the daemon call runs off the main actor.
@MainActor @Observable
public final class SearchModel {
    /// What ``onSearched`` reports for one finished search.
    public struct LogEntry: Equatable, Sendable {
        /// The query searched.
        public let query: String
        /// The mode searched.
        public let mode: SearchMode
        /// The results returned (0 on failure).
        public let resultCount: Int
        /// The daemon's reported time, if any.
        public let tookUs: UInt64?
        /// Milliseconds as seen by the app.
        public let roundTripMs: Double
        /// The error's text, or nil.
        public let error: String?
    }

    /// The text in the search box; set it, then call ``refresh()``.
    public var query = ""
    /// The mode to search in.
    public var mode: SearchMode = .names
    /// The current results.
    public private(set) var items: [ResultItem] = []
    /// Where the current search is.
    public private(set) var phase: SearchPhase = .idle
    /// The daemon's time for the results showing, if it reported one.
    public private(set) var lastTookUs: UInt64?
    /// Called once for each search that completes as the newest generation, with its outcome (for the debug log).
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

    /// Creates a model.
    ///
    /// - Parameters:
    ///   - names: The backend for name searches.
    ///   - content: The backend for content and symbol searches; a separate connection so a slow grep doesn't block name searches.
    public init(names: SearchBackend, content: SearchBackend) {
        self.names = names
        self.content = content
    }

    /// Runs the search for the current ``query`` and ``mode`` and publishes the outcome.
    ///
    /// A query that is blank, is the "?" cheat sheet, or has an empty content pattern clears the results and sends nothing.
    /// A query ending in a half-typed filter (`foo size:`) leaves everything as it is. A stale answer, or one cancelled by a
    /// newer refresh, is dropped.
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

    /// Whether a content search has no pattern yet: an empty pattern would match every line.
    private static func emptyPattern(_ q: String, _ mode: SearchMode) -> Bool {
        mode == .names ? QuerySplit.contentSearch(q)?.pattern.isEmpty == true : QuerySplit.split(q).pattern.isEmpty
    }

    /// A query with nothing but spaces searches nothing.
    ///
    /// - Parameter q: The typed query.
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
            // 50 rows fill the panel with room to scroll; more only slows the answer.
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

    /// Tells the observers a search finished; `phase` is already updated.
    private func report(_ q: String, _ mode: SearchMode, _ n: Int, _ took: UInt64?, _ started: Date, _ err: String?) {
        onSearched?(
            LogEntry(query: q, mode: mode, resultCount: n, tookUs: took, roundTripMs: Date().timeIntervalSince(started) * 1000, error: err))
        onSettled?(phase)
    }
}
