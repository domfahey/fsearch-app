import Foundation
import Testing
@testable import FSearchKit

@Suite struct SearchLogTests {
    /// A fresh temp directory per test; the log file lives inside it.
    func sandbox() -> (dir: URL, file: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fsk-log-\(UUID())", isDirectory: true)
        return (dir, dir.appendingPathComponent("searches.jsonl"))
    }
    let e = SearchModel.LogEntry(query: "main", mode: .names, resultCount: 3, tookUs: 120, roundTripMs: 1.5, error: nil)

    /// One valid JSON line for `query`, encoded the way the log encodes it.
    func validLine(_ query: String) throws -> String {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        let r = SearchLog.Record(time: Date(timeIntervalSince1970: 1_800_000_000), query: query, mode: "names", results: 1, tookUs: nil, roundTripMs: 0, error: nil)
        return String(decoding: try enc.encode(r), as: UTF8.self)
    }

    @Test func appendsAndReads() {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file)
        log.append(e, at: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(log.entries() == [SearchLog.Record(time: Date(timeIntervalSince1970: 1_800_000_000), query: "main", mode: "names", results: 3, tookUs: 120, roundTripMs: 1.5, error: nil)])
    }
    @Test func keepsOnlyTheNewestCap() {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file, cap: 5)
        for i in 0..<12 { log.append(SearchModel.LogEntry(query: "q\(i)", mode: .names, resultCount: 0, tookUs: nil, roundTripMs: 0, error: nil), at: Date()) }
        #expect(log.entries().map(\.query) == ["q7", "q8", "q9", "q10", "q11"])
    }
    @Test func clearEmptiesIt() {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file)
        log.append(e, at: Date()); log.clear()
        #expect(log.entries().isEmpty)
    }
    @Test func skipsCorruptLinesAndKeepsAppendingAfterAPartialLine() throws {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        try FileManager.default.createDirectory(at: s.dir, withIntermediateDirectories: true)
        // A garbage line, one valid record, then a partial line with no newline.
        try "garbage\n\(try validLine("main"))\n{\"tru".write(to: s.file, atomically: true, encoding: .utf8)
        let log = SearchLog(file: s.file)
        #expect(log.entries().map(\.query) == ["main"])
        log.append(SearchModel.LogEntry(query: "next", mode: .names, resultCount: 0, tookUs: nil, roundTripMs: 0, error: nil), at: Date())
        #expect(log.entries().map(\.query) == ["main", "next"])
    }
    @Test func compactsAtTwiceTheCap() throws {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file, cap: 3)
        for i in 0..<7 { log.append(SearchModel.LogEntry(query: "q\(i)", mode: .names, resultCount: 0, tookUs: nil, roundTripMs: 0, error: nil), at: Date()) }
        let lines = try String(contentsOf: s.file, encoding: .utf8).split(separator: "\n")
        #expect(lines.count <= 6)
        #expect(log.entries().map(\.query) == ["q4", "q5", "q6"])
    }

    @Test func appendWritesInPlaceInsteadOfRewriting() throws {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file, cap: 100)
        log.append(e, at: Date())
        let inode = { try? FileManager.default.attributesOfItem(atPath: s.file.path)[.systemFileNumber] as? UInt64 }
        let before = inode()
        log.append(e, at: Date())
        #expect(before != nil)
        #expect(inode() == before)
        #expect(log.entries().count == 2)
    }
}
