/// Content queries: the typed text is the pattern, except fsearch filters
/// (`ext:rs`, `in:~/x`, `mtime:<7d`), which narrow the files searched.
/// Sending the text as `grep:...` instead would turn a second word into a
/// name filter.
public enum QuerySplit {
    static let keys: Set<String> = ["ext", "type", "kind", "in", "size", "mtime", "modified", "re", "path", "limit"]

    /// The pattern keeps the typed spacing (only leading and trailing spaces
    /// are dropped); filters are returned joined by single spaces.
    public static func split(_ query: String) -> (pattern: String, filters: String) {
        var pattern = "", filters: [Substring] = []
        var space = ""   // whitespace typed before the current word
        var i = query.startIndex
        while i < query.endIndex {
            if query[i].isWhitespace {
                space.append(query[i])
                i = query.index(after: i)
                continue
            }
            let start = i
            while i < query.endIndex, !query[i].isWhitespace { i = query.index(after: i) }
            let word = query[start..<i]
            if isFilter(word) {
                filters.append(word)   // its surrounding spacing is dropped
            } else {
                if !pattern.isEmpty { pattern += space }
                pattern += word
            }
            space = ""
        }
        return (pattern, filters.joined(separator: " "))
    }

    private static func isFilter(_ word: Substring) -> Bool {
        guard let colon = word.firstIndex(of: ":"), word.index(after: colon) < word.endIndex else { return false }
        return keys.contains(String(word[..<colon]))
    }
}
