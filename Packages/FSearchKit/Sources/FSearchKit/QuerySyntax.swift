/// The query cheat sheet the panel shows when the query is just "?".
/// Mirrors the daemon's filter keys (query.rs `Query::filter`).
public enum QuerySyntax {
    public static let cheatSheet: [(syntax: String, meaning: String)] = [
        ("ext:rs,md", "files with these extensions"),
        ("in:~/Developer", "only under this folder"),
        ("type:code", "a kind of file: code, doc, image, video, audio, archive, font, app"),
        ("kind:dir", "file, dir or link"),
        ("size:>10mb", "size range: <, >, or 1mb..5mb"),
        ("mtime:<7d", "modified in the last 7 days (m, h, d, w, mo, y)"),
        ("path:src/.*test", "regex on the full path"),
        ("limit:200", "how many results (the panel shows up to 1000)"),
        ("re:^main\\.", "regex on the file name"),
        ("in:\"~/My Stuff\"", "quote a value that has spaces"),
        ("'exact ^prefix suffix$ !not", "how a plain word matches"),
        ("grep:text", "search inside files (also regex:, sym:)"),
        ("\"ext:rs\"", "inside files: a leading quote makes a filter word text"),
    ]

    /// The cheat sheet replaces results when the query is exactly "?".
    public static func isCheatSheet(_ query: String) -> Bool { query == "?" }
}
