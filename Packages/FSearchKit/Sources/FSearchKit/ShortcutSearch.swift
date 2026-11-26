import Foundation

/// Runs one-shot file searches for automation entry points (such as Shortcuts App Intents)
/// without opening the launcher panel.
public enum ShortcutSearch: Sendable {
    /// Default number of matching files returned when the caller does not specify a limit.
    public static let defaultLimit = 50
    /// Hard upper bound on returned files, matching the launcher panel's result cap.
    public static let maxLimit = 1000

    /// True if ``run(query:mode:limit:backend:)`` would search file contents: content or symbol mode, or a
    /// `grep:`/`content:`/`regex:`/`sym:`/`symbol:` key in a names-mode query (checked after the same sanitizing).
    ///
    /// - Parameters:
    ///   - query: The search query, as passed to ``run(query:mode:limit:backend:)``.
    ///   - mode: The search mode.
    /// - Returns: Whether the search would read text inside files.
    public static func readsFileContents(query: String, mode: SearchMode) -> Bool {
        mode != .names || QuerySplit.contentSearch(SearchURL.sanitize(query)) != nil
    }

    /// Searches for matching files and returns their absolute paths in ranked order, deduplicated.
    ///
    /// - Parameters:
    ///   - query: The search query, using FSearch's normal query syntax and filters.
    ///   - mode: Whether to match file names, text inside files, or symbol definitions.
    ///   - limit: Maximum number of file paths to return (capped at ``maxLimit``; values `<= 0` return `[]`).
    ///     An explicit `limit:` filter in `query` overrides `limit` (still capped at ``maxLimit``).
    ///   - backend: The daemon connection to search against.
    /// - Returns: Ranked, deduplicated absolute file paths.
    /// - Throws: ``DaemonError`` when the daemon cannot be reached, is indexing, or rejects the query.
    public static func run(
        query: String,
        mode: SearchMode = .names,
        limit: Int = defaultLimit,
        backend: SearchBackend
    ) async throws -> [String] {
        let clean = SearchURL.sanitize(query)
        guard !SearchModel.isBlank(clean) else { return [] }

        switch mode {
        case .names:
            if let content = QuerySplit.contentSearch(clean) {
                return try await runGrep(
                    filters: content.q, pattern: content.pattern, grepMode: content.mode, limit: limit, backend: backend)
            }
            let hasExplicitLimit = QuerySplit.hasLimitWord(clean)
            if !hasExplicitLimit && limit <= 0 { return [] }
            let requestLimit = min(max(1, limit), maxLimit)
            let outputCap = hasExplicitLimit ? min(max(0, QuerySplit.limit(clean) ?? maxLimit), maxLimit) : requestLimit
            let forms = SearchModel.normalForms(clean)
            if forms.count == 1 {
                let reply = try await backend.search(clean, limit: requestLimit)
                return deduped(reply.hits.map(\.path), limit: outputCap)
            }
            var hits: [Hit] = []
            for form in forms {
                let reply = try await backend.search(form, limit: requestLimit)
                hits.append(contentsOf: reply.hits)
            }
            return deduped(SearchModel.merged(hits, limit: outputCap).map(\.path), limit: outputCap)
        case .content, .symbols:
            let (pattern, filters) = QuerySplit.split(clean)
            return try await runGrep(
                filters: filters, pattern: pattern, grepMode: mode == .symbols ? .symbol : .literal,
                limit: limit, backend: backend)
        }
    }

    private static func runGrep(
        filters: String, pattern: String, grepMode: GrepMode, limit: Int, backend: SearchBackend
    ) async throws -> [String] {
        guard !pattern.isEmpty else { return [] }
        let hasExplicitLimit = QuerySplit.hasLimitWord(filters)
        if !hasExplicitLimit && limit <= 0 { return [] }
        let requestLimit = min(max(1, limit), maxLimit)
        let outputCap = hasExplicitLimit ? min(max(0, QuerySplit.limit(filters) ?? maxLimit), maxLimit) : requestLimit
        let grepFilters: String
        if !hasExplicitLimit && requestLimit != defaultLimit {
            grepFilters = filters.isEmpty ? "limit:\(requestLimit)" : "\(filters) limit:\(requestLimit)"
        } else {
            grepFilters = filters
        }
        let reply = try await backend.grep(q: grepFilters, pattern: pattern, mode: grepMode)
        return deduped(reply.files.map(\.path), limit: outputCap)
    }

    private static func deduped(_ paths: [String], limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var seen: Set<String> = []
        var out: [String] = []
        out.reserveCapacity(min(paths.count, limit))
        for path in paths where seen.insert(path).inserted {
            out.append(path)
            if out.count == limit { break }
        }
        return out
    }
}
