import Foundation

/// Pure helpers behind the debug windows (Index Details, Search Log); no UI, so they are testable.
public enum DebugFormat {
    /// Newest first; `filter` matches the query, ignoring case.
    ///
    /// - Parameters:
    ///   - rows: Records oldest first, as stored.
    ///   - filter: Text to look for in each query; empty keeps every row.
    public static func shown(_ rows: [SearchLog.Record], filter: String) -> [SearchLog.Record] {
        let r = rows.reversed()
        return filter.isEmpty ? Array(r) : r.filter { $0.query.localizedCaseInsensitiveContains(filter) }
    }

    /// JSON lines (oldest first, as in the log file) for the export. A record that fails to encode is skipped.
    public static func jsonl(_ rows: [SearchLog.Record]) -> Data {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        var out = Data()
        for r in rows {
            guard let d = try? enc.encode(r) else { continue }
            out.append(d); out.append(UInt8(ascii: "\n"))
        }
        return out
    }

    /// Formats the daemon's own time (microseconds) as milliseconds; an en dash when unknown.
    public static func daemonMs(_ us: UInt64?) -> String {
        us.map { String(format: "%.2f ms", Double($0) / 1000) } ?? "–"
    }

    /// Formats the app-side round trip time in milliseconds.
    public static func roundTrip(_ ms: Double) -> String { String(format: "%.1f ms", ms) }

    /// Formats a byte count the way Finder does.
    public static func bytes(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }

    /// The daemon's data folder: the directory holding its socket.
    ///
    /// - Parameter socketPath: The daemon's socket path.
    public static func dataDir(socketPath: String) -> URL {
        URL(fileURLWithPath: socketPath).deletingLastPathComponent()
    }

    /// Size and modification date of a file, to skip re-reading an unchanged
    /// one. nil when the file is missing.
    ///
    /// - Parameter file: The file to stat.
    public struct FileStamp: Equatable, Sendable {
        /// Size in bytes (0 if unreadable).
        public let size: UInt64
        /// Last modification date, if known.
        public let modified: Date?

        /// Reads the file's attributes; fails when the file doesn't exist.
        public init?(of file: URL) {
            guard let a = try? FileManager.default.attributesOfItem(atPath: file.path) else { return nil }
            size = (a[.size] as? NSNumber)?.uint64Value ?? 0
            modified = a[.modificationDate] as? Date
        }
    }

    /// Non-empty lines of `s`.
    public static func lines(_ s: String) -> [String] {
        s.split(separator: "\n").map(String.init)
    }

    /// The last `n` lines of a file, reading at most `maxBytes` from its end
    /// (read-only). A partial first line from the byte cut is dropped.
    ///
    /// Reading only a tail keeps a large log cheap to show.
    ///
    /// - Parameters:
    ///   - file: The file to read.
    ///   - n: How many lines to return.
    ///   - maxBytes: The most bytes to read from the end.
    /// - Returns: The lines joined by newlines, or an empty string if the file can't be read.
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
