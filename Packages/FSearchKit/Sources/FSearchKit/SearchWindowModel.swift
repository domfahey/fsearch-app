import Foundation
import Observation

/// Observable state for one Everything-style search window.
///
/// Each window owns its own instance so multiple windows can search, filter, sort, and select independently
/// without cancelling each other's queries.
@MainActor @Observable
public final class SearchWindowModel {
    /// Current query text in the search field.
    public var query = ""
    /// Active search scope (file names, inside files, or definitions).
    public var mode: SearchMode = .names
    /// Active match toggles (match case, whole word, regex, search in path).
    public var options = SearchMatchOptions()
    /// Active clickable filter chips.
    public var chips: [SearchFilterChip] = []
    /// Current table sort column and direction; changing it re-sorts ``rows`` immediately in memory.
    public var sort: SearchWindowSort = .defaultSort {
        didSet {
            if sort != oldValue {
                rows = SearchWindowRow.sort(rawRows, by: sort)
            }
        }
    }
    /// Sorted rows currently displayed in the table.
    public private(set) var rows: [SearchWindowRow] = []
    /// Where the current search is (idle, loading, results, indexing, or failed).
    public private(set) var phase: SearchPhase = .idle
    /// The daemon's reported execution time in microseconds for the current rows.
    public private(set) var lastTookUs: UInt64?
    /// App-measured round-trip time in milliseconds for the current rows.
    public private(set) var lastRoundTripMs: Double?
    /// True when the daemon returned as many hits as the effective result limit (indicating more matches may exist).
    public private(set) var hitCap = false
    /// Called once for each finished search (wired to the debug search log when debug mode is on).
    @ObservationIgnored public var onSearched: ((SearchModel.LogEntry) -> Void)?
    /// Called with the final phase whenever a search settles (wired to daemon recovery).
    @ObservationIgnored public var onSettled: ((SearchPhase) -> Void)?

    @ObservationIgnored private let names: SearchBackend
    @ObservationIgnored private let content: SearchBackend
    @ObservationIgnored private var rawRows: [SearchWindowRow] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var requestedKey: RequestKey?
    @ObservationIgnored private var inflight: Task<([SearchWindowRow], UInt64, Bool), Error>?

    private struct RequestKey: Equatable {
        let query: String
        let mode: SearchMode
        let options: SearchMatchOptions
        let chips: [SearchFilterChip]
    }

    /// Creates an independent window search model.
    ///
    /// - Parameters:
    ///   - names: Backend for file-name searches.
    ///   - content: Backend for content and symbol searches.
    public init(names: SearchBackend, content: SearchBackend) {
        self.names = names
        self.content = content
    }

    /// Current page request descriptor (ready for future upstream daemon paging).
    public var pageRequest: SearchWindowQuery.PageRequest {
        let compiled = SearchWindowQuery.compile(rawQuery: query, mode: mode, options: options, chips: chips)
        let q: String
        let lim: Int
        switch compiled {
        case let .names(composed, limit, _): (q, lim) = (composed, limit)
        case let .grep(filters, pattern, _):
            (q, lim) = (filters.isEmpty ? pattern : "\(pattern) \(filters)", SearchWindowQuery.defaultLimit)
        case .empty: (q, lim) = ("", SearchWindowQuery.defaultLimit)
        }
        return SearchWindowQuery.PageRequest(query: q, mode: mode, offset: 0, limit: lim, sort: sort)
    }

    /// Adds a filter chip if an identical chip is not already active.
    public func addChip(_ chip: SearchFilterChip) {
        guard !chips.contains(where: { $0.id == chip.id }) else { return }
        chips.append(chip)
    }

    /// Removes the filter chip with the given `id`.
    public func removeChip(id: String) {
        chips.removeAll { $0.id == id }
    }

    /// Toggles `chip`: removes it if present, otherwise adds it.
    public func toggleChip(_ chip: SearchFilterChip) {
        if chips.contains(where: { $0.id == chip.id }) {
            removeChip(id: chip.id)
        } else {
            addChip(chip)
        }
    }

    /// Resets match toggles and active filter chips.
    public func clearFilters() {
        options = SearchMatchOptions()
        chips = []
    }

    /// Applies a saved search or built-in preset to this window.
    public func apply(_ saved: SavedSearch) {
        query = saved.query
        mode = saved.mode
        options = saved.options
        chips = saved.chips
        sort = saved.sort
    }

    /// Captures the window's current query, mode, match options, chips, and sort as a ``SavedSearch``.
    public func snapshot(name: String) -> SavedSearch {
        SavedSearch(name: name, query: query, mode: mode, options: options, chips: chips, sort: sort, isBuiltIn: false)
    }

    /// Runs the search for the current query, mode, options, and chips, publishing sorted rows when finished.
    public func refresh() async {
        let halfTyped = !options.regex && QuerySplit.endsInHalfTypedFilter(query, mode: mode)
        let currentKey = RequestKey(query: query, mode: mode, options: options, chips: chips)
        if halfTyped, let prev = requestedKey, prev.mode == mode, prev.options == options, prev.chips == chips,
            QuerySplit.halfTypedExtends(query, answered: prev.query, mode: mode)
        {
            return
        }

        generation += 1
        inflight?.cancel()
        inflight = nil
        let gen = generation
        requestedKey = currentKey

        if halfTyped {
            clearResults()
            return
        }

        let compiled = SearchWindowQuery.compile(rawQuery: query, mode: mode, options: options, chips: chips)
        if case .empty = compiled {
            clearResults()
            return
        }

        phase = .loading
        let started = ContinuousClock.now
        let logQuery = query
        let logMode = mode
        let task = Task { try await self.execute(compiled) }
        inflight = task
        defer { if gen == generation { inflight = nil } }

        do {
            let (fetched, took, capped) = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            guard gen == generation else { return }
            let elapsed = started.duration(to: .now)
            let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            rawRows = fetched
            rows = SearchWindowRow.sort(fetched, by: sort)
            phase = .results
            lastTookUs = took
            lastRoundTripMs = ms
            hitCap = capped
            onSearched?(
                SearchModel.LogEntry(query: logQuery, mode: logMode, resultCount: rows.count, tookUs: took, roundTripMs: ms, error: nil))
            onSettled?(phase)
        } catch is CancellationError {
            return
        } catch let e as DaemonError {
            guard gen == generation else { return }
            rawRows = []
            rows = []
            lastTookUs = nil
            lastRoundTripMs = nil
            hitCap = false
            phase = if case .indexing = e { .indexing } else { .failed(e) }
            let elapsed = started.duration(to: .now)
            let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            onSearched?(
                SearchModel.LogEntry(
                    query: logQuery, mode: logMode, resultCount: 0, tookUs: nil, roundTripMs: ms, error: String(describing: e)))
            onSettled?(phase)
        } catch {
            guard gen == generation else { return }
            rawRows = []
            rows = []
            lastTookUs = nil
            lastRoundTripMs = nil
            hitCap = false
            phase = .failed(.badReply(String(describing: error)))
            let elapsed = started.duration(to: .now)
            let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            onSearched?(
                SearchModel.LogEntry(
                    query: logQuery, mode: logMode, resultCount: 0, tookUs: nil, roundTripMs: ms, error: String(describing: error)))
            onSettled?(phase)
        }
    }

    private func clearResults() {
        rawRows = []
        rows = []
        phase = .idle
        lastTookUs = nil
        lastRoundTripMs = nil
        hitCap = false
    }

    private func execute(_ compiled: SearchWindowQuery.CompiledQuery) async throws -> ([SearchWindowRow], UInt64, Bool) {
        switch compiled {
        case .empty:
            return ([], 0, false)
        case let .names(q, limit, clientFilter):
            let forms = SearchModel.normalForms(q)
            let hits: [Hit]
            let took: UInt64
            if forms.count == 1 {
                let reply = try await names.search(q, limit: limit)
                hits = reply.hits
                took = reply.tookUs
            } else {
                var all: [Hit] = []
                var sum: UInt64 = 0
                for form in forms {
                    let reply = try await names.search(form, limit: limit)
                    all.append(contentsOf: reply.hits)
                    sum = sum &+ reply.tookUs
                }
                hits = SearchModel.merged(all, limit: limit)
                took = sum
            }
            let capped = hits.count >= limit
            let filtered: [Hit]
            if let clientFilter {
                filtered = hits.filter { clientFilter.matches(path: $0.path) }
            } else {
                filtered = hits
            }
            let cappedRows = Array(filtered.prefix(SearchWindowQuery.defaultLimit)).map { SearchWindowRow(item: .file($0)) }
            return (cappedRows, took, capped)
        case let .grep(filters, pattern, grepMode):
            let reply = try await content.grep(q: filters, pattern: pattern, mode: grepMode)
            let allLines = reply.files.flatMap { file in
                file.matches.map { SearchWindowRow(item: .line(path: file.path, match: $0)) }
            }
            let capped = !reply.complete || allLines.count >= SearchWindowQuery.defaultLimit
            return (Array(allLines.prefix(SearchWindowQuery.defaultLimit)), reply.tookUs, capped)
        }
    }
}
