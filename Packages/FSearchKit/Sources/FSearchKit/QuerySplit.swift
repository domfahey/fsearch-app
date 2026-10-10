/// Content queries: the typed text is the pattern, except fsearch filters
/// (`ext:rs`, `in:~/x`, `mtime:<7d`), which narrow the files searched.
/// Sending the text as `grep:...` instead would turn a second word into a
/// name filter.
public enum QuerySplit {
    static let keys: Set<String> = ["ext", "type", "kind", "in", "size", "mtime", "modified", "re", "path", "limit"]

    public static func split(_ query: String) -> (pattern: String, filters: String) {
        var pattern: [Substring] = [], filters: [Substring] = []
        for word in query.split(separator: " ", omittingEmptySubsequences: true) {
            if let colon = word.firstIndex(of: ":"), keys.contains(String(word[..<colon])), word.index(after: colon) < word.endIndex {
                filters.append(word)
            } else {
                pattern.append(word)
            }
        }
        return (pattern.joined(separator: " "), filters.joined(separator: " "))
    }
}
