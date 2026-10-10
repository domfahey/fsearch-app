import Foundation

/// Pure helpers behind the debug windows (Index Details, Search Log).
public enum DebugFormat {
    /// Newest first; `filter` matches the query, ignoring case.
    public static func shown(_ rows: [SearchLog.Record], filter: String) -> [SearchLog.Record] {
        let r = rows.reversed()
        return filter.isEmpty ? Array(r) : r.filter { $0.query.localizedCaseInsensitiveContains(filter) }
    }

    /// JSON lines (oldest first, as in the log file) for the export.
    public static func jsonl(_ rows: [SearchLog.Record]) -> Data {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        var out = Data()
        for r in rows {
            guard let d = try? enc.encode(r) else { continue }
            out.append(d); out.append(UInt8(ascii: "\n"))
        }
        return out
    }

    public static func daemonMs(_ us: UInt64?) -> String {
        us.map { String(format: "%.2f ms", Double($0) / 1000) } ?? "–"
    }

    public static func roundTrip(_ ms: Double) -> String { String(format: "%.1f ms", ms) }

    public static func bytes(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    /// Non-empty lines.
    public static func lines(_ s: String) -> [String] {
        s.split(separator: "\n").map(String.init)
    }

    /// The last `n` lines of a file, reading at most `maxBytes` from its end
    /// (read-only). A partial first line from the byte cut is dropped.
    public static func tail(of file: URL, lines n: Int, maxBytes: Int = 64 * 1024) -> String {
        guard let fh = try? FileHandle(forReadingFrom: file) else { return "" }
        defer { try? fh.close() }
        guard let size = try? fh.seekToEnd() else { return "" }
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        try? fh.seek(toOffset: start)
        guard let data = try? fh.readToEnd() else { return "" }
        var text = String(decoding: data, as: UTF8.self)
        if start > 0 {
            guard let nl = text.firstIndex(of: "\n") else { return "" }
            text = String(text[text.index(after: nl)...])
        }
        return lines(text).suffix(n).joined(separator: "\n")
    }
}
