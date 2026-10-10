/// Content queries: the typed text is the pattern, except fsearch filters
/// (`ext:rs`, `in:~/x`, `mtime:<7d`), which narrow the files searched. Keys
/// match case-sensitively, as in the daemon. Unlike the daemon, a word is a
/// filter only when it has a value: a bare key (`kind: Deployment`,
/// `limit: 10`) and a word that starts with a quote (`"ext:rs"`) are text,
/// since sent as filters they'd be daemon errors or a match-all `path:`.
/// Sending the text as `grep:...` instead would turn a second word into a
/// name filter.
///
/// Words split like the daemon's `split_words` (query.rs): on spaces, with a
/// "double quoted" run kept in one word. Unlike the daemon, a word keeps its
/// quotes here, so filters sent back to the daemon split the same way again.
///
/// The key lists and word rules must stay in step with the daemon's `query.rs`; a mismatch
/// would send a filter as a pattern or the reverse.
public enum QuerySplit {
    /// The filter keys the daemon understands (query.rs `Query::filter`).
    static let keys: Set<String> = ["ext", "type", "kind", "in", "size", "mtime", "modified", "re", "path", "limit"]
    /// Keys that make the daemon answer a search with matching lines (query.rs `filter`).
    static let contentKeys: [String: GrepMode] = [
        "grep": .literal, "content": .literal, "regex": .regex, "sym": .symbol, "symbol": .symbol,
    ]

    /// The pattern keeps the typed spacing (only leading and trailing spaces
    /// are dropped); filters are returned joined by single spaces.
    ///
    /// - Parameter query: The typed text.
    /// - Returns: The pattern to search for and the filters that narrow the files.
    public static func split(_ query: String) -> (pattern: String, filters: String) {
        var pattern = "", filters: [String] = []
        for (space, word) in spacedWords(query) {
            if isFilter(word) {
                filters.append(word)  // its surrounding spacing is dropped
            } else {
                if !pattern.isEmpty { pattern += space }
                pattern += word
            }
        }
        return (pattern, filters.joined(separator: " "))
    }

    /// The words of a query, quotes kept.
    ///
    /// - Parameter s: The typed text.
    public static func words(_ s: String) -> [String] { spacedWords(s).map(\.word) }

    /// A word as the daemon reads it: quotes removed.
    ///
    /// - Parameter word: A word from ``words(_:)``.
    public static func unquoted(_ word: String) -> String { word.replacingOccurrences(of: "\"", with: "") }

    /// A name query holding `grep:`/`content:`/`regex:`/`sym:`/`symbol:` is a
    /// content search: that word's value is the pattern (possibly empty; the last one wins,
    /// as in the daemon) and the other words pick the files.
    ///
    /// - Parameter query: The typed text.
    /// - Returns: The filters, the pattern and the mode, or nil when the query has no content key.
    public static func contentSearch(_ query: String) -> (q: String, pattern: String, mode: GrepMode)? {
        var rest: [String] = [], found: (String, GrepMode)?
        for word in words(query) {
            let plain = unquoted(word)
            // An empty value counts too: the daemon still runs a content search for it.
            if let colon = plain.firstIndex(of: ":"), let mode = contentKeys[String(plain[..<colon])] {
                found = (String(plain[plain.index(after: colon)...]), mode)
            } else {
                rest.append(word)
            }
        }
        return found.map { (rest.joined(separator: " "), $0.0, $0.1) }
    }

    /// True if the daemon will read a `limit:` word in the query (quotes
    /// dropped, as it does), whatever its value.
    ///
    /// - Parameter query: The typed text.
    public static func hasLimitWord(_ query: String) -> Bool {
        words(query).contains { unquoted($0).hasPrefix("limit:") }
    }

    /// The typed `limit:` value (the last one wins, as in the daemon), or nil
    /// when there is none or it isn't a number.
    ///
    /// - Parameter query: The typed text.
    public static func limit(_ query: String) -> Int? {
        guard let last = words(query).map(unquoted).last(where: { $0.hasPrefix("limit:") }) else { return nil }
        return Int(last.dropFirst("limit:".count))
    }

    /// True if the query has a content key, so a name search would get lines back.
    ///
    /// - Parameter query: The typed text.
    public static func hasContentKey(_ query: String) -> Bool { contentSearch(query) != nil }

    /// The daemon's `type:` values (query.rs `TYPES`, plus `app`).
    static let typeValues: Set<String> = ["code", "doc", "image", "video", "audio", "archive", "font", "app"]
    /// The daemon's `kind:` values.
    static let kindValues: Set<String> = ["file", "f", "dir", "folder", "d", "link", "symlink", "l"]

    /// True while the last word, with no space typed since, is a filter whose
    /// value is still being typed: nothing after the colon (`foo size:`), a
    /// strict prefix of a `type:`/`kind:` value (`type:c`, `kind:fi`, or after
    /// a comma: `type:code,`), or a range cut short (`size:1mb..`, `size:>`,
    /// `mtime:<`). The daemon would answer with an error, or match nothing.
    ///
    /// The half-typed rule keeps the previous results on screen instead of flashing an error.
    ///
    /// - Parameters:
    ///   - query: The typed text.
    ///   - mode: The search mode. Outside names mode a word starting with a quote is text (see ``split(_:)``), never a
    ///     filter; the daemon drops a name query's quotes, so there it can still be one.
    public static func endsInHalfTypedFilter(_ query: String, mode: SearchMode = .names) -> Bool {
        guard let last = words(query).last, query.last != " " else { return false }
        if mode != .names && last.hasPrefix("\"") { return false }
        let plain = unquoted(last)
        guard let colon = plain.firstIndex(of: ":") else { return false }
        let key = String(plain[..<colon]), value = String(plain[plain.index(after: colon)...])
        guard keys.contains(key) else { return false }
        if value.isEmpty { return true }
        switch key {
        case "type": return isStrictPrefix(String(value.split(separator: ",", omittingEmptySubsequences: false).last ?? ""), of: typeValues)
        case "kind": return isStrictPrefix(value, of: kindValues)
        case "size", "mtime", "modified": return [".", "<", ">", "="].contains { value.hasSuffix($0) }
        default: return false
        }
    }

    /// `s` starts some value but isn't one yet.
    private static func isStrictPrefix(_ s: String, of values: Set<String>) -> Bool {
        !values.contains(s) && values.contains { $0.hasPrefix(s) }
    }

    /// Each word with the spaces typed before it.
    private static func spacedWords(_ s: String) -> [(space: String, word: String)] {
        var out: [(String, String)] = [], space = "", cur = "", quoted = false
        for c in s {
            if c == " " && !quoted {
                if cur.isEmpty { space.append(c) } else { out.append((space, cur)); (space, cur) = (" ", "") }
                continue
            }
            if c == "\"" { quoted.toggle() }
            cur.append(c)
        }
        if !cur.isEmpty { out.append((space, cur)) }
        return out
    }

    /// `key:value` with a known key, no quote before the colon, and a value
    /// that isn't empty once its quotes are dropped.
    private static func isFilter(_ word: String) -> Bool {
        guard let colon = word.firstIndex(of: ":"), keys.contains(String(word[..<colon])) else { return false }
        return !unquoted(String(word[word.index(after: colon)...])).isEmpty
    }
}
