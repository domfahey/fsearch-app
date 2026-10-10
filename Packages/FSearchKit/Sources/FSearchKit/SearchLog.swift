import Foundation

/// Debug mode's search log: JSON lines, newest last, capped. Stays on this Mac.
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

    public init(file: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/FSearch/searches.jsonl"), cap: Int = 10_000) {
        self.file = file
        self.cap = cap
    }

    private static func mode(_ m: SearchMode) -> String {
        switch m { case .names: "names"; case .content: "content"; case .symbols: "symbols" }
    }

    public func append(_ e: SearchModel.LogEntry, at t: Date) {
        lock.lock(); defer { lock.unlock() }
        let r = Record(time: t, query: e.query, mode: Self.mode(e.mode), results: e.resultCount, tookUs: e.tookUs, roundTripMs: e.roundTripMs, error: e.error)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        var all = read()
        all.append(r)
        // Trim in batches, once 10% over the cap (every append for tiny caps).
        if all.count > cap + cap / 10 { all = Array(all.suffix(cap)) }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let body = all.compactMap { try? enc.encode($0) }.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n") + "\n"
        try? body.write(to: file, atomically: true, encoding: .utf8)
    }

    public func entries() -> [Record] {
        lock.lock(); defer { lock.unlock() }
        return Array(read().suffix(cap))
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: file)
    }

    private func read() -> [Record] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return data.split(separator: UInt8(ascii: "\n")).compactMap { try? dec.decode(Record.self, from: Data($0)) }
    }
}
