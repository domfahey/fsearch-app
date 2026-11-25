import Foundation

/// The query cheat sheet the panel shows when the query is just "?".
/// Mirrors the daemon's filter keys (query.rs `Query::filter`).
public enum QuerySyntax {
    /// The syntax lines, each with a short meaning, in display order.
    public static let cheatSheet: [(syntax: String, meaning: String)] = [
        ("ext:rs,md", String(localized: "files with these extensions", bundle: .module)),
        ("in:~/Developer", String(localized: "only under this folder", bundle: .module)),
        (
            "type:code",
            String(localized: "a kind of file: code, doc, image, video, audio, archive, font, app", bundle: .module)
        ),
        ("kind:dir", String(localized: "file, dir or link", bundle: .module)),
        ("size:>10mb", String(localized: "size range: <, >, or 1mb..5mb", bundle: .module)),
        ("mtime:<7d", String(localized: "modified in the last 7 days (m, h, d, w, mo, y)", bundle: .module)),
        ("path:src/.*test", String(localized: "regex on the full path", bundle: .module)),
        ("limit:200", String(localized: "how many results (the panel shows up to 1000)", bundle: .module)),
        ("re:^main\\.", String(localized: "regex on the file name", bundle: .module)),
        ("in:\"~/My Stuff\"", String(localized: "quote a value that has spaces", bundle: .module)),
        ("'exact ^prefix suffix$ !not", String(localized: "how a plain word matches", bundle: .module)),
        ("grep:text", String(localized: "search inside files (also regex:, sym:)", bundle: .module)),
        ("\"ext:rs\"", String(localized: "inside files: wrap a filter word in quotes to search for it as text", bundle: .module)),
    ]

    /// The cheat sheet replaces results when the query is exactly "?".
    public static func isCheatSheet(_ query: String) -> Bool { query == "?" }
}
