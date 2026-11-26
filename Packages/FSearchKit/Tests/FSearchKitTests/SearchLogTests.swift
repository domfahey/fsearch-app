import Foundation
import Synchronization
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
        let r = SearchLog.Record(
            time: Date(timeIntervalSince1970: 1_800_000_000), query: query, mode: "names", results: 1, tookUs: nil, roundTripMs: 0,
            error: nil)
        return String(decoding: try enc.encode(r), as: UTF8.self)
    }

    @Test func appendsAndReads() {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file)
        log.append(e, at: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(
            log.entries() == [
                SearchLog.Record(
                    time: Date(timeIntervalSince1970: 1_800_000_000), query: "main", mode: "names", results: 3, tookUs: 120,
                    roundTripMs: 1.5, error: nil)
            ])
    }
    @Test func keepsOnlyTheNewestCap() {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file, cap: 5)
        for i in 0..<12 {
            log.append(
                SearchModel.LogEntry(query: "q\(i)", mode: .names, resultCount: 0, tookUs: nil, roundTripMs: 0, error: nil), at: Date())
        }
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
        let lines = { try String(contentsOf: s.file, encoding: .utf8).split(separator: "\n").count }
        for i in 0..<6 {
            log.append(
                SearchModel.LogEntry(query: "q\(i)", mode: .names, resultCount: 0, tookUs: nil, roundTripMs: 0, error: nil), at: Date())
        }
        #expect(try lines() == 6, "2x cap lines is not yet over the limit")
        log.append(SearchModel.LogEntry(query: "q6", mode: .names, resultCount: 0, tookUs: nil, roundTripMs: 0, error: nil), at: Date())
        #expect(try lines() == 3, "the 7th line triggers one rewrite down to cap")
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

    @Test func appendsDoNotAddBlankLines() throws {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file, cap: 100)
        for i in 0..<3 {
            log.append(
                SearchModel.LogEntry(query: "q\(i)", mode: .names, resultCount: 0, tookUs: nil, roundTripMs: 0, error: nil), at: Date())
        }
        let raw = try String(contentsOf: s.file, encoding: .utf8)
        #expect(!raw.contains("\n\n"))
        #expect(raw.split(separator: "\n", omittingEmptySubsequences: false).count == 4)
    }

    @Test func negativeCapAndExternalDeleteAreHandledCleanly() throws {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let zero = SearchLog(file: s.file, cap: -5)
        zero.append(e, at: Date())
        #expect(zero.entries().isEmpty)

        let log = SearchLog(file: s.file, cap: 2)
        for i in 0..<3 {
            log.append(
                SearchModel.LogEntry(query: "q\(i)", mode: .names, resultCount: 0, tookUs: nil, roundTripMs: 0, error: nil), at: Date())
        }
        try FileManager.default.removeItem(at: s.file)
        log.append(
            SearchModel.LogEntry(query: "after-delete", mode: .names, resultCount: 0, tookUs: nil, roundTripMs: 0, error: nil), at: Date())
        #expect(log.entries().map(\.query) == ["after-delete"])
    }

    @Test func appendAsyncFlushesBeforeEntriesAndClear() {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file)
        for i in 0..<5 {
            log.appendAsync(
                SearchModel.LogEntry(query: "a\(i)", mode: .names, resultCount: i, tookUs: nil, roundTripMs: 0, error: nil), at: Date())
        }
        #expect(log.entries().map(\.query) == ["a0", "a1", "a2", "a3", "a4"])
        log.appendAsync(e, at: Date())
        log.clear()
        log.flush()
        #expect(log.entries().isEmpty)
    }

    // MARK: age limit

    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func line(_ query: String, age: TimeInterval) throws -> String {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        let r = SearchLog.Record(
            time: Self.now.addingTimeInterval(-age), query: query, mode: "names", results: 1, tookUs: nil, roundTripMs: 0, error: nil)
        return String(decoding: try enc.encode(r), as: UTF8.self)
    }
    private let day: TimeInterval = 86_400

    @Test func entriesHidesRecordsOlderThanSevenDays() throws {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        try FileManager.default.createDirectory(at: s.dir, withIntermediateDirectories: true)
        try [line("old", age: 7 * day + 1), line("edge", age: 7 * day - 1), line("new", age: 60)].joined(separator: "\n")
            .appending("\n").write(to: s.file, atomically: true, encoding: .utf8)
        let log = SearchLog(file: s.file, now: { Self.now })
        #expect(log.entries().map(\.query) == ["edge", "new"])
    }

    @Test func appendDropsExpiredRecordsFromTheFile() throws {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        try FileManager.default.createDirectory(at: s.dir, withIntermediateDirectories: true)
        try [line("old", age: 8 * day), line("new", age: 60)].joined(separator: "\n")
            .appending("\n").write(to: s.file, atomically: true, encoding: .utf8)
        let log = SearchLog(file: s.file, now: { Self.now })
        log.append(e, at: Self.now)
        let raw = try String(contentsOf: s.file, encoding: .utf8)
        #expect(!raw.contains("old"))
        #expect(log.entries().map(\.query) == ["new", "main"])
    }

    @Test func recordsAgeOutAsTheClockAdvances() {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let clock = Mutex(Self.now)
        let log = SearchLog(file: s.file, now: { clock.withLock { $0 } })
        log.append(e, at: Self.now)
        #expect(log.entries().count == 1)
        clock.withLock { $0 = Self.now.addingTimeInterval(8 * 86_400) }
        #expect(log.entries().isEmpty)
        log.append(e, at: clock.withLock { $0 })
        #expect(log.entries().count == 1)
    }

    @Test func atomicRewriteCreatesTheFileOwnerOnlyEvenWithALooseUmask() throws {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        try FileManager.default.createDirectory(at: s.dir, withIntermediateDirectories: true)
        let old = umask(0); defer { umask(old) }
        try SearchLog.writeAtomically(Data("x\n".utf8), to: s.file)
        let mode = try FileManager.default.attributesOfItem(atPath: s.file.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(try String(contentsOf: s.file, encoding: .utf8) == "x\n")
        #expect(try FileManager.default.contentsOfDirectory(atPath: s.dir.path) == ["searches.jsonl"])
    }
}
