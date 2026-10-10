import Foundation
import Testing
@testable import FSearchKit

@Suite struct SearchLogCoverageTests {
    func sandbox() -> (dir: URL, file: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fsk-logc-\(UUID())", isDirectory: true)
        return (dir, dir.appendingPathComponent("sub/searches.jsonl"))
    }
    func entry(_ q: String, mode: SearchMode = .names, took: UInt64? = nil, error: String? = nil, ms: Double = 0) -> SearchModel.LogEntry {
        SearchModel.LogEntry(query: q, mode: mode, resultCount: 0, tookUs: took, roundTripMs: ms, error: error)
    }

    @Test func createsMissingDirectories() {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file)
        #expect(log.entries().isEmpty, "a missing file reads as empty")
        log.append(entry("a"), at: Date())
        #expect(FileManager.default.fileExists(atPath: s.file.path))
        #expect(log.entries().count == 1)
    }

    @Test func everyModeIsLoggedByName() {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file)
        for m in [SearchMode.names, .content, .symbols] { log.append(entry("q", mode: m), at: Date()) }
        #expect(log.entries().map(\.mode) == ["names", "content", "symbols"])
    }

    @Test func allFieldsRoundTrip() {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file)
        let t = Date(timeIntervalSince1970: 1_700_000_123)
        log.append(SearchModel.LogEntry(query: "🏡 \"q\"", mode: .content, resultCount: 7, tookUs: 42, roundTripMs: 3.5, error: "boom"), at: t)
        #expect(log.entries() == [SearchLog.Record(time: t, query: "🏡 \"q\"", mode: "content", results: 7, tookUs: 42, roundTripMs: 3.5, error: "boom")])
    }

    @Test func unencodableRecordIsDroppedQuietly() {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file)
        log.append(entry("nan", ms: .nan), at: Date())
        #expect(log.entries().isEmpty)
        log.append(entry("ok"), at: Date())
        #expect(log.entries().map(\.query) == ["ok"])
    }

    @Test func unwritableFileNeverCrashes() throws {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        // The log "file" is a directory: opening it for writing fails.
        try FileManager.default.createDirectory(at: s.file, withIntermediateDirectories: true)
        let log = SearchLog(file: s.file)
        log.append(entry("a"), at: Date())
        #expect(log.entries().isEmpty)
    }

    @Test func existingLongFileIsCompactedOnFirstAppend() throws {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        try FileManager.default.createDirectory(at: s.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let a = SearchLog(file: s.file, cap: 100)
        for i in 0..<10 { a.append(entry("old\(i)"), at: Date()) }
        // A new instance seeds its line count from the file.
        let b = SearchLog(file: s.file, cap: 3)
        b.append(entry("new"), at: Date())
        #expect(b.entries().map(\.query) == ["old8", "old9", "new"])
        let lines = try String(contentsOf: s.file, encoding: .utf8).split(separator: "\n")
        #expect(lines.count == 3)
    }

    @Test func corruptLinesCountTowardCompactionButNotEntries() throws {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        try FileManager.default.createDirectory(at: s.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try (Array(repeating: "junk", count: 8).joined(separator: "\n") + "\n").write(to: s.file, atomically: true, encoding: .utf8)
        let log = SearchLog(file: s.file, cap: 3)
        log.append(entry("a"), at: Date())
        #expect(log.entries().map(\.query) == ["a"])
        #expect(try String(contentsOf: s.file, encoding: .utf8).split(separator: "\n").count == 1, "junk was compacted away")
    }

    @Test func zeroCapKeepsNothing() throws {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file, cap: 0)
        log.append(entry("a"), at: Date())
        log.append(entry("b"), at: Date())
        #expect(log.entries().isEmpty)
        #expect(try String(contentsOf: s.file, encoding: .utf8).isEmpty)
    }

    @Test func clearThenAppendStartsFresh() {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file, cap: 2)
        for i in 0..<3 { log.append(entry("a\(i)"), at: Date()) }
        log.clear()
        log.clear()
        #expect(log.entries().isEmpty && !FileManager.default.fileExists(atPath: s.file.path))
        log.append(entry("b"), at: Date())
        #expect(log.entries().map(\.query) == ["b"])
    }

    @Test func entriesReturnOnlyTheNewestCapEvenIfFileHoldsMore() throws {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let big = SearchLog(file: s.file, cap: 50)
        for i in 0..<10 { big.append(entry("q\(i)"), at: Date()) }
        let small = SearchLog(file: s.file, cap: 4)
        #expect(small.entries().map(\.query) == ["q6", "q7", "q8", "q9"])
    }

    @Test func fileEndingWithoutNewlineGetsOneBeforeTheNextRecord() throws {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file)
        log.append(entry("a"), at: Date())
        // Chop the trailing newline off.
        var data = try Data(contentsOf: s.file)
        data.removeLast()
        try data.write(to: s.file)
        log.append(entry("b"), at: Date())
        #expect(log.entries().map(\.query) == ["a", "b"])
    }

    @Test func concurrentAppendsAreAllKept() async {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file, cap: 10_000)
        let (threads, per) = (8, 50)
        await withTaskGroup(of: Void.self) { g in
            for t in 0..<threads {
                g.addTask { for i in 0..<per { log.append(self.entry("t\(t)-\(i)"), at: Date()) } }
            }
        }
        let got = log.entries().map(\.query)
        #expect(got.count == threads * per)
        #expect(Set(got).count == threads * per, "no record lost or duplicated")
        for t in 0..<threads {
            #expect(got.filter { $0.hasPrefix("t\(t)-") } == (0..<per).map { "t\(t)-\($0)" }, "per-thread order holds")
        }
    }

    @Test func concurrentAppendsAcrossCompactionStayWithinBounds() async {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let log = SearchLog(file: s.file, cap: 10)
        await withTaskGroup(of: Void.self) { g in
            for t in 0..<4 { g.addTask { for i in 0..<40 { log.append(self.entry("t\(t)-\(i)"), at: Date()) } } }
        }
        #expect(log.entries().count == 10)
    }
}
