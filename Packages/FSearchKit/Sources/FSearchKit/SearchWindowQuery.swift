import Foundation

/// Match behavior toggles for the Everything-style search window.
public struct SearchMatchOptions: Codable, Equatable, Hashable, Sendable {
    /// Match letter case exactly instead of case-insensitively.
    public var matchCase: Bool
    /// Match whole words only (bounded by non-word characters or start/end).
    public var wholeWord: Bool
    /// Treat the typed query terms as a regular expression.
    public var regex: Bool
    /// Match against the full file path instead of only the file name (names mode).
    public var searchInPath: Bool

    /// Creates match options; all toggles default to off.
    public init(matchCase: Bool = false, wholeWord: Bool = false, regex: Bool = false, searchInPath: Bool = false) {
        self.matchCase = matchCase
        self.wholeWord = wholeWord
        self.regex = regex
        self.searchInPath = searchInPath
    }

    /// True when any match toggle is active.
    public var hasAnyOption: Bool { matchCase || wholeWord || regex || searchInPath }
}

/// A clickable filter pill in the search window, mapping directly to a daemon filter word (`ext:`, `in:`, `size:`, `mtime:`, `type:`, `kind:`).
public struct SearchFilterChip: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// Which daemon filter key the chip represents.
    public enum Kind: String, Codable, CaseIterable, Hashable, Sendable {
        /// File category (`type:code`, `type:doc`, …).
        case type
        /// File extension list (`ext:swift,md`).
        case ext
        /// Entry kind (`kind:file`, `kind:dir`, `kind:link`).
        case kind
        /// Folder scope (`in:~/Developer`).
        case folder = "in"
        /// File size range (`size:>10mb`).
        case size
        /// Modification age (`mtime:<7d`).
        case modified = "mtime"

        /// The daemon filter key written before the colon.
        public var filterKey: String { rawValue }
    }

    /// The filter kind.
    public let kind: Kind
    /// The raw filter value (without the key prefix or outer quotes).
    public let value: String
    /// Short display title for the pill.
    public let title: String

    /// Stable identifier derived from the filter kind and normalized value.
    public var id: String { "\(kind.rawValue):\(value)" }

    /// Creates a filter chip.
    ///
    /// - Parameters:
    ///   - kind: The daemon filter category.
    ///   - value: The filter value (trimmed of surrounding whitespace).
    ///   - title: Display label; defaults to `<key>:<value>`.
    public init(kind: Kind, value: String, title: String? = nil) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kind = kind
        self.value = trimmed
        self.title = title ?? "\(kind.filterKey):\(trimmed)"
    }

    /// The daemon filter token for this chip, quoting values that contain spaces.
    public var token: String {
        "\(kind.filterKey):\(SearchWindowQuery.quoteFilterValue(value))"
    }

    /// Built-in file-type filter chips.
    public static var typePresets: [SearchFilterChip] {
        [
            SearchFilterChip(kind: .type, value: "code", title: String(localized: "Code", bundle: .module)),
            SearchFilterChip(kind: .type, value: "doc", title: String(localized: "Documents", bundle: .module)),
            SearchFilterChip(kind: .type, value: "image", title: String(localized: "Images", bundle: .module)),
            SearchFilterChip(kind: .type, value: "video", title: String(localized: "Video", bundle: .module)),
            SearchFilterChip(kind: .type, value: "audio", title: String(localized: "Audio", bundle: .module)),
            SearchFilterChip(kind: .type, value: "archive", title: String(localized: "Archives", bundle: .module)),
            SearchFilterChip(kind: .type, value: "app", title: String(localized: "Apps", bundle: .module)),
        ]
    }

    /// Built-in entry-kind filter chips.
    public static var kindPresets: [SearchFilterChip] {
        [
            SearchFilterChip(kind: .kind, value: "file", title: String(localized: "Files only", bundle: .module)),
            SearchFilterChip(kind: .kind, value: "dir", title: String(localized: "Folders only", bundle: .module)),
            SearchFilterChip(kind: .kind, value: "link", title: String(localized: "Aliases", bundle: .module)),
        ]
    }

    /// Built-in size filter chips.
    public static var sizePresets: [SearchFilterChip] {
        [
            SearchFilterChip(kind: .size, value: "<100kb", title: String(localized: "Under 100 KB", bundle: .module)),
            SearchFilterChip(kind: .size, value: ">1mb", title: String(localized: "Over 1 MB", bundle: .module)),
            SearchFilterChip(kind: .size, value: ">10mb", title: String(localized: "Over 10 MB", bundle: .module)),
            SearchFilterChip(kind: .size, value: ">100mb", title: String(localized: "Over 100 MB", bundle: .module)),
        ]
    }

    /// Built-in modification-time filter chips.
    public static var modifiedPresets: [SearchFilterChip] {
        [
            SearchFilterChip(kind: .modified, value: "<1h", title: String(localized: "Past hour", bundle: .module)),
            SearchFilterChip(kind: .modified, value: "<24h", title: String(localized: "Past 24 hours", bundle: .module)),
            SearchFilterChip(kind: .modified, value: "<7d", title: String(localized: "Past 7 days", bundle: .module)),
            SearchFilterChip(kind: .modified, value: "<30d", title: String(localized: "Past 30 days", bundle: .module)),
            SearchFilterChip(kind: .modified, value: "<1y", title: String(localized: "Past year", bundle: .module)),
        ]
    }

    /// Built-in common folder scope chips.
    public static var folderPresets: [SearchFilterChip] {
        [
            SearchFilterChip(kind: .folder, value: "~/Desktop", title: String(localized: "Desktop", bundle: .module)),
            SearchFilterChip(kind: .folder, value: "~/Documents", title: String(localized: "Documents", bundle: .module)),
            SearchFilterChip(kind: .folder, value: "~/Downloads", title: String(localized: "Downloads", bundle: .module)),
            SearchFilterChip(kind: .folder, value: "~/Developer", title: String(localized: "Developer", bundle: .module)),
        ]
    }

    /// Creates a normalized extension chip from user input (e.g. `".swift, .md"` -> `ext:swift,md`), or nil if empty.
    public static func extensionChip(_ input: String) -> SearchFilterChip? {
        let exts =
            input
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased() }
            .filter { !$0.isEmpty }
        guard !exts.isEmpty else { return nil }
        let joined = exts.joined(separator: ",")
        return SearchFilterChip(kind: .ext, value: joined, title: "ext:\(joined)")
    }

    /// Creates a folder scope chip from a file-system path (abbreviating home with `~`), or nil if empty.
    public static func folderChip(_ path: String) -> SearchFilterChip? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let abbreviated = (trimmed as NSString).abbreviatingWithTildeInPath
        let name = (abbreviated as NSString).lastPathComponent
        let title = name.isEmpty || name == "/" ? abbreviated : "in:\(name)"
        return SearchFilterChip(kind: .folder, value: abbreviated, title: title)
    }
}

/// Composes typed text, match toggles, and clickable filter chips into daemon requests for the v2 search window.
public enum SearchWindowQuery {
    /// Default maximum rows requested by a search window query (matching the panel's hard cap until daemon paging lands).
    public static let defaultLimit = 1000

    /// Future-ready paging request contract (offset, limit, and sort order) for server-side daemon paging.
    public struct PageRequest: Equatable, Sendable {
        /// The composed daemon query string.
        public let query: String
        /// The search mode.
        public let mode: SearchMode
        /// Zero-based row offset (currently always 0 until upstream `fsearch` adds `offset`).
        public let offset: Int
        /// Maximum number of rows requested.
        public let limit: Int
        /// Requested column sort order.
        public let sort: SearchWindowSort

        /// Creates a paging request descriptor.
        public init(
            query: String, mode: SearchMode, offset: Int = 0, limit: Int = SearchWindowQuery.defaultLimit,
            sort: SearchWindowSort = .defaultSort
        ) {
            self.query = query
            self.mode = mode
            self.offset = max(0, offset)
            self.limit = max(1, limit)
            self.sort = sort
        }
    }

    /// Client-side post-filter for multi-term match rules (`matchCase`, `wholeWord`, `searchInPath`) when the daemon's
    /// single `re:`/`path:` regex slot can only express one term directly.
    public struct ClientFilter: Equatable, Sendable {
        /// Plain terms that must all match.
        public let terms: [String]
        /// Match letter case exactly.
        public let matchCase: Bool
        /// Require word boundaries around each term.
        public let wholeWord: Bool
        /// Match against the full path instead of only the file name.
        public let searchInPath: Bool

        /// Creates a client-side verifier.
        public init(terms: [String], matchCase: Bool, wholeWord: Bool, searchInPath: Bool) {
            self.terms = terms
            self.matchCase = matchCase
            self.wholeWord = wholeWord
            self.searchInPath = searchInPath
        }

        /// True when `path` satisfies every term under the configured match rules.
        public func matches(path: String) -> Bool {
            let haystack = searchInPath ? path : (path as NSString).lastPathComponent
            let compareOptions: String.CompareOptions = matchCase ? [] : [.caseInsensitive]
            for term in terms {
                if !wholeWord {
                    if haystack.range(of: term, options: compareOptions) == nil { return false }
                } else {
                    if !containsWholeWord(term, in: haystack, options: compareOptions) { return false }
                }
            }
            return true
        }

        private func containsWholeWord(_ term: String, in haystack: String, options: String.CompareOptions) -> Bool {
            var searchStart = haystack.startIndex
            while searchStart < haystack.endIndex,
                let range = haystack.range(of: term, options: options, range: searchStart..<haystack.endIndex)
            {
                let leftOK = range.lowerBound == haystack.startIndex || !isWordChar(haystack[haystack.index(before: range.lowerBound)])
                let rightOK = range.upperBound == haystack.endIndex || !isWordChar(haystack[range.upperBound])
                if leftOK && rightOK { return true }
                searchStart = haystack.index(after: range.lowerBound)
            }
            return false
        }

        private func isWordChar(_ ch: Character) -> Bool {
            ch == "_" || ch.isLetter || ch.isNumber
        }
    }

    /// Compiled request ready to send to `SearchBackend`.
    public enum CompiledQuery: Equatable, Sendable {
        /// Nothing to search (blank query and no active chips, or empty content pattern).
        case empty
        /// File-name search with an effective limit and optional client-side post-filter.
        case names(query: String, limit: Int, clientFilter: ClientFilter?)
        /// Content or symbol search.
        case grep(filters: String, pattern: String, mode: GrepMode)
    }

    /// Escapes Rust `regex` metacharacters so literal text matches verbatim.
    public static func regexEscape(_ text: String) -> String {
        let meta = Set("\\.+*?()|[]{}^$#&-~")
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            if meta.contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// Quotes a filter value if it contains whitespace so the daemon's word splitter keeps it in one token.
    public static func quoteFilterValue(_ value: String) -> String {
        guard value.contains(where: \.isWhitespace) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: ""))\""
    }

    /// Compiles raw query text, search mode, match toggles, and active filter chips into a daemon request.
    ///
    /// - Parameters:
    ///   - rawQuery: The user's typed text in the search field.
    ///   - mode: Whether to search names, file contents, or definitions.
    ///   - options: Active Match Case, Whole Word, Regex, and Search in Path toggles.
    ///   - chips: Active clickable filter chips.
    ///   - defaultLimit: Result cap when no explicit `limit:` filter is typed (clamped to `defaultLimit`).
    /// - Returns: A compiled query ready for execution, or `.empty` when nothing should be sent.
    public static func compile(
        rawQuery: String, mode: SearchMode, options: SearchMatchOptions = SearchMatchOptions(),
        chips: [SearchFilterChip] = [], defaultLimit: Int = defaultLimit
    ) -> CompiledQuery {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let chipTokens = chips.map(\.token)

        switch mode {
        case .names:
            // Inline grep:/content:/regex:/sym:/symbol: in names mode switches to content search.
            if let inline = QuerySplit.contentSearch(trimmed) {
                guard !inline.pattern.isEmpty else { return .empty }
                let mergedFilters = ([inline.q] + chipTokens).filter { !$0.isEmpty }.joined(separator: " ")
                return compileGrep(pattern: inline.pattern, filters: mergedFilters, baseMode: inline.mode, options: options)
            }
            let combinedRaw = ([trimmed] + chipTokens).filter { !$0.isEmpty }.joined(separator: " ")
            guard !combinedRaw.isEmpty else { return .empty }

            let explicitLimit = QuerySplit.limit(combinedRaw)
            let effectiveLimit = min(max(1, explicitLimit ?? defaultLimit), SearchWindowQuery.defaultLimit)

            // Fast path: no match toggles active — send the exact combined query straight to the daemon.
            if !options.hasAnyOption {
                return .names(query: combinedRaw, limit: effectiveLimit, clientFilter: nil)
            }

            // Separate daemon filter words from plain search terms.
            let (plainText, existingFilters) = QuerySplit.split(trimmed)
            var filterParts: [String] = []
            if !existingFilters.isEmpty { filterParts.append(existingFilters) }
            filterParts.append(contentsOf: chipTokens)

            guard !plainText.isEmpty else {
                // Only filters/chips are present — match toggles have no text terms to transform.
                let q = filterParts.joined(separator: " ")
                return q.isEmpty ? .empty : .names(query: q, limit: effectiveLimit, clientFilter: nil)
            }

            let filterKey = options.searchInPath ? "path" : "re"
            if options.regex {
                let body = options.wholeWord ? "\\b(?:\(plainText))\\b" : plainText
                let flagged = options.matchCase ? "(?-i)\(body)" : body
                filterParts.append("\(filterKey):\(quoteFilterValue(flagged))")
                return .names(query: filterParts.joined(separator: " "), limit: effectiveLimit, clientFilter: nil)
            }

            let terms = QuerySplit.words(plainText).map { $0.replacingOccurrences(of: "\"", with: "") }.filter { !$0.isEmpty }
            guard let anchor = terms.max(by: { $0.count < $1.count }) else {
                let q = filterParts.joined(separator: " ")
                return q.isEmpty ? .empty : .names(query: q, limit: effectiveLimit, clientFilter: nil)
            }
            if terms.count == 1 {
                let escaped = regexEscape(anchor)
                let body = options.wholeWord ? "\\b(?:\(escaped))\\b" : escaped
                let flagged = options.matchCase ? "(?-i)\(body)" : body
                filterParts.append("\(filterKey):\(quoteFilterValue(flagged))")
                return .names(query: filterParts.joined(separator: " "), limit: effectiveLimit, clientFilter: nil)
            }

            // Multiple plain words with match toggles: narrow on the daemon using the longest term in `re:`/`path:`
            // (plus exact filename tokens when not searching full paths), then verify all terms client-side.
            let anchorEscaped = regexEscape(anchor)
            let anchorBody = options.wholeWord ? "\\b(?:\(anchorEscaped))\\b" : anchorEscaped
            let anchorFlagged = options.matchCase ? "(?-i)\(anchorBody)" : anchorBody
            filterParts.append("\(filterKey):\(quoteFilterValue(anchorFlagged))")
            if !options.searchInPath {
                for term in terms {
                    filterParts.append("'\(quoteFilterValue(term))")
                }
            }
            let client = ClientFilter(
                terms: terms, matchCase: options.matchCase, wholeWord: options.wholeWord, searchInPath: options.searchInPath)
            return .names(query: filterParts.joined(separator: " "), limit: effectiveLimit, clientFilter: client)

        case .content, .symbols:
            let (pattern, existingFilters) = QuerySplit.split(trimmed)
            guard !pattern.isEmpty else { return .empty }
            let mergedFilters = ([existingFilters] + chipTokens).filter { !$0.isEmpty }.joined(separator: " ")
            let baseMode: GrepMode = mode == .symbols ? .symbol : .literal
            return compileGrep(pattern: pattern, filters: mergedFilters, baseMode: baseMode, options: options)
        }
    }

    private static func compileGrep(
        pattern: String, filters: String, baseMode: GrepMode, options: SearchMatchOptions
    ) -> CompiledQuery {
        if baseMode == .symbol {
            return .grep(filters: filters, pattern: pattern, mode: .symbol)
        }
        let useRegex = baseMode == .regex || options.regex || options.matchCase || options.wholeWord
        guard useRegex else {
            return .grep(filters: filters, pattern: pattern, mode: .literal)
        }
        let core = (baseMode == .regex || options.regex) ? pattern : regexEscape(pattern)
        let bounded = options.wholeWord ? "\\b(?:\(core))\\b" : core
        let flagged = options.matchCase ? "(?-i)\(bounded)" : "(?i)\(bounded)"
        return .grep(filters: filters, pattern: flagged, mode: .regex)
    }
}
