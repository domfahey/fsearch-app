/// Content queries: the typed text is the pattern, except fsearch filters
/// (`ext:rs`, `in:~/x`, `mtime:<7d`), which narrow the files searched. As in
/// the daemon, a known key with an empty value (`ext:`) is still a filter, and
/// keys match case-sensitively.
/// Sending the text as `grep:...` instead would turn a second word into a
/// name filter.
///
/// Words split like the daemon's `split_words` (query.rs): on spaces, with a
/// "double quoted" run kept in one word. Unlike the daemon, a word keeps its
/// quotes here, so filters sent back to the daemon split the same way again.
public enum QuerySplit {
    static let keys: Set<String> = ["ext", "type", "kind", "in", "size", "mtime", "modified", "re", "path", "limit"]
    /// Keys that make the daemon answer a search with matching lines (query.rs `filter`).
    static let contentKeys: [String: GrepMode] = ["grep": .literal, "content": .literal, "regex": .regex, "sym": .symbol, "symbol": .symbol]

    /// The pattern keeps the typed spacing (only leading and trailing spaces
    /// are dropped); filters are returned joined by single spaces.
    public static func split(_ query: String) -> (pattern: String, filters: String) {
        var pattern = "", filters: [String] = []
        for (space, word) in spacedWords(query) {
            if isFilter(word) {
                filters.append(word)   // its surrounding spacing is dropped
            } else {
                if !pattern.isEmpty { pattern += space }
                pattern += word
            }
        }
        return (pattern, filters.joined(separator: " "))
    }

    /// The words of a query, quotes kept.
    public static func words(_ s: String) -> [String] { spacedWords(s).map(\.word) }

    /// A word as the daemon reads it: quotes removed.
    public static func unquoted(_ word: String) -> String { word.replacingOccurrences(of: "\"", with: "") }

    /// A name query holding `grep:`/`content:`/`regex:`/`sym:`/`symbol:` is a
    /// content search: that word's value is the pattern (possibly empty; the last one wins,
    /// as in the daemon) and the other words pick the files.
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

    /// True if the query has a content key, so a name search would get lines back.
    public static func hasContentKey(_ query: String) -> Bool { contentSearch(query) != nil }

    /// True while the last word is a filter key with nothing after the colon
    /// and no space typed since (`foo size:`): the user is still typing the
    /// value, and the daemon would answer with an error (or match nothing).
    public static func endsInHalfTypedFilter(_ query: String) -> Bool {
        guard let last = words(query).last, query.last != " " else { return false }
        let plain = unquoted(last)
        guard let colon = plain.firstIndex(of: ":"), plain.index(after: colon) == plain.endIndex else { return false }
        return keys.contains(String(plain[..<colon]))
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

    private static func isFilter(_ word: String) -> Bool {
        let plain = unquoted(word)
        guard let colon = plain.firstIndex(of: ":") else { return false }
        return keys.contains(String(plain[..<colon]))
    }
}
