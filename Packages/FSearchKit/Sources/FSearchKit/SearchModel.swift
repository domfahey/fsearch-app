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
    /// The current results (at most ``shownLimit``); see ``resultsAreCurrent``.
    public private(set) var items: [ResultItem] = []
    /// Where the current search is.
    public private(set) var phase: SearchPhase = .idle
    /// The daemon's time for the results showing, if it reported one.
    public private(set) var lastTookUs: UInt64?
    /// The query and mode that `items` (and `phase`) answer. It lags `query`
    /// and `mode` from the moment they change until that search settles.
    public private(set) var answered: (query: String, mode: SearchMode) = ("", .names)
    /// True only while `items` answer the query and mode now in the box: false
    /// from the keystroke (or mode change) until its search settles, while a
    /// half-typed filter keeps older rows up, and when a late reply answers a
    /// query that has since changed. Acting on a row (↵, ⌘↵, ⌘Y, ⌘K, ⌘1–9)
    /// should wait for it, or a stale row is opened.
    public var resultsAreCurrent: Bool { answered.query == query && answered.mode == mode }
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
    /// The query and mode of the newest refresh that searched or cleared.
    @ObservationIgnored private var requested: (query: String, mode: SearchMode) = ("", .names)
    /// The backend call of the newest refresh; a newer refresh cancels it, so a
    /// hung daemon costs one timeout, not one per keystroke.
    @ObservationIgnored private var inflight: Task<([ResultItem], UInt64), Error>?

    /// The most rows the panel shows, however many the daemon sends back
    /// (`limit:100000` asks for that many).
    public nonisolated static let shownLimit = 1000

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
    /// A query ending in a half-typed filter (`foo size:`, `type:c`) sends nothing: it leaves everything as it is while it
    /// extends the last query in the same mode, and clears the results otherwise. A stale answer, or one cancelled by a
    /// newer refresh, is dropped. At most ``shownLimit`` rows are published.
    public func refresh() async {
        // A filter still being typed (`foo size:`) is not a query yet. While
        // it extends the last query in the same mode (see
        // QuerySplit.halfTypedExtends), keep what is showing and let any
        // search already under way finish. Otherwise (the query was replaced,
        // a tail was pasted, or the mode changed) those rows answer something
        // else: clear them, still sending nothing.
        let halfTyped = QuerySplit.endsInHalfTypedFilter(query, mode: mode)
        if halfTyped && mode == requested.mode && QuerySplit.halfTypedExtends(query, answered: requested.query, mode: mode) { return }
        generation += 1
        inflight?.cancel()
        inflight = nil
        let gen = generation, q = query, mode = self.mode
        requested = (q, mode)
        if halfTyped {
            (items, phase, lastTookUs, answered) = ([], .idle, nil, (q, mode))
            return
        }
        // Nothing to send: a blank query, the "?" cheat sheet, or a content
        // query made only of filters, or a name query whose grep:/sym: has no
        // value yet (an empty pattern matches every line).
        if Self.isBlank(q) || QuerySyntax.isCheatSheet(q) || Self.emptyPattern(q, mode) {
            (items, phase, lastTookUs, answered) = ([], .idle, nil, (q, mode))
            return
        }
        phase = .loading
        let started = Date()
        let task = Task { try await self.run(q, mode) }
        inflight = task
        do {
            let (all, took) = try await task.value
            let found = Array(all.prefix(Self.shownLimit))
            guard gen == generation else { return }
            (items, phase, lastTookUs, answered) = (found, .results, took, (q, mode))
            report(q, mode, found.count, took, started, nil)
        } catch is CancellationError {
            // Superseded by a newer refresh (or the caller went away): no state change.
            return
        } catch let e as DaemonError {
            guard gen == generation else { return }
            (items, lastTookUs, answered) = ([], nil, (q, mode))
            if case .indexing = e { phase = .indexing } else { phase = .failed(e) }
            report(q, mode, 0, nil, started, String(describing: e))
        } catch {
            guard gen == generation else { return }
            (items, phase, lastTookUs, answered) = ([], .failed(.badReply(String(describing: error))), nil, (q, mode))
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
            // A typed `limit:` overrides it (the request then leaves it out).
            let forms = Self.normalForms(q)
            if forms.count == 1 {
                let r = try await names.search(q, limit: 50)
                return (r.hits.map(ResultItem.file), r.tookUs)
            }
            var hits: [Hit] = [], took: UInt64 = 0
            for form in forms {
                let r = try await names.search(form, limit: 50)
                (hits, took) = (hits + r.hits, took + r.tookUs)
            }
            return (Self.merged(hits, limit: QuerySplit.limit(q) ?? 50).map(ResultItem.file), took)
        case .content, .symbols:
            let (pattern, filters) = QuerySplit.split(q)
            let r = try await content.grep(q: filters, pattern: pattern, mode: mode == .symbols ? .symbol : .literal)
            return (lines(r), r.tookUs)
        }
    }

    /// The query, then its other Unicode normal forms. The daemon compares
    /// bytes, and Mac apps write accented names in NFD while typing gives NFC,
    /// so "café" would miss Café files. Plain ASCII has one form.
    nonisolated static func normalForms(_ q: String) -> [String] {
        if q.unicodeScalars.allSatisfy(\.isASCII) { return [q] }
        var out: [String] = []
        for form in [q, q.decomposedStringWithCanonicalMapping, q.precomposedStringWithCanonicalMapping]
        where !out.contains(where: { $0.unicodeScalars.elementsEqual(form.unicodeScalars) }) {
            out.append(form)
        }
        return out
    }

    /// Hits from several searches: one per path (String equality treats NFC
    /// and NFD paths as one) with its best score, best first, up to `limit`.
    nonisolated static func merged(_ hits: [Hit], limit: Int) -> [Hit] {
        var best: [String: (order: Int, hit: Hit)] = [:]
        for (i, h) in hits.enumerated() where best[h.path].map({ h.score > $0.hit.score }) ?? true {
            best[h.path] = (best[h.path]?.order ?? i, h)
        }
        let sorted = best.values.sorted { ($0.hit.score, -$0.order) > ($1.hit.score, -$1.order) }
        return sorted.prefix(max(0, limit)).map(\.hit)
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
