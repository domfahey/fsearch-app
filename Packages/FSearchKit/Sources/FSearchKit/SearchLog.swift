import Foundation

/// Debug mode's search log: JSON lines, newest last, capped. Stays on this Mac.
///
/// Keep one shared instance per file: the in-memory line count is only
/// correct for the instance that wrote the file. Appends go straight to the
/// end of the file; once it holds more than 2x `cap` lines it is rewritten
/// once with only the newest `cap`. Write errors are ignored on purpose:
/// this is a debug log, and a failed write must never disturb a search.
public final class SearchLog: @unchecked Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public let time: Date
        public let query: String
        public let mode: String
        public let results: Int
        public let tookUs: UInt64?
        public let roundTripMs: Double
        public let error: String?
    }

    public let file: URL
    private let cap: Int
    private let lock = NSLock()
    /// Physical lines in the file, seeded by one read on first use.
    private var lineCount: Int?

    public init(
        file: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/FSearch/searches.jsonl"),
        cap: Int = 10_000
    ) {
        self.file = file
        self.cap = cap
    }

    private static func mode(_ m: SearchMode) -> String {
        switch m {
        case .names: "names";
        case .content: "content";
        case .symbols: "symbols"
        }
    }

    public func append(_ e: SearchModel.LogEntry, at t: Date) {
        lock.lock(); defer { lock.unlock() }
        let r = Record(
            time: t, query: e.query, mode: Self.mode(e.mode), results: e.resultCount, tookUs: e.tookUs, roundTripMs: e.roundTripMs,
            error: e.error)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        guard var line = try? enc.encode(r) else { return }
        line.append(UInt8(ascii: "\n"))

        if lineCount == nil { lineCount = rawLines().count }
        let dir = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        secure()
        guard let fh = try? FileHandle(forUpdating: file) else { return }
        defer { try? fh.close() }
        let end = (try? fh.seekToEnd()) ?? 0
        if end > 0 {
            // A partial last line (say, from a crash) must not swallow the new record.
            try? fh.seek(toOffset: end - 1)
            if (try? fh.read(upToCount: 1)) != Data([UInt8(ascii: "\n")]) {
                _ = try? fh.seekToEnd()
                try? fh.write(contentsOf: Data([UInt8(ascii: "\n")]))
            }
        }
        _ = try? fh.seekToEnd()
        try? fh.write(contentsOf: line)
        lineCount = (lineCount ?? 0) + 1

        if let n = lineCount, n > 2 * cap {
            compact()
        }
    }

    public func entries() -> [Record] {
        lock.lock(); defer { lock.unlock() }
        return Array(readRecords().suffix(cap))
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: file)
        lineCount = 0
    }

    /// Rewrite the file with only the newest `cap` valid records. Caller holds the lock.
    private func compact() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        let kept = readRecords().suffix(cap)
        let body =
            kept.compactMap { try? enc.encode($0) }
            .map { String(decoding: $0, as: UTF8.self) }
            .joined(separator: "\n") + (kept.isEmpty ? "" : "\n")
        try? body.write(to: file, atomically: true, encoding: .utf8)
        secure()
        lineCount = kept.count
    }

    /// The log holds search text: folder 0700, file 0600, both left out of backups.
    /// Run after every create and after `compact` (an atomic rewrite makes a new file).
    /// Caller holds the lock.
    private func secure() {
        let fm = FileManager.default
        let dir = file.deletingLastPathComponent()
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        for var url in [dir, file] {
            var v = URLResourceValues(); v.isExcludedFromBackup = true
            try? url.setResourceValues(v)
        }
    }

    /// Non-empty lines in the file, valid or not. Caller holds the lock.
    private func rawLines() -> [Data] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return data.split(separator: UInt8(ascii: "\n")).map { Data($0) }
    }

    /// Every valid record in file order; corrupt lines are skipped. Caller holds the lock.
    private func readRecords() -> [Record] {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return rawLines().compactMap { try? dec.decode(Record.self, from: $0) }
    }
}
