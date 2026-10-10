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
        log.append(
            SearchModel.LogEntry(query: "🏡 \"q\"", mode: .content, resultCount: 7, tookUs: 42, roundTripMs: 3.5, error: "boom"), at: t)
        #expect(
            log.entries() == [
                SearchLog.Record(time: t, query: "🏡 \"q\"", mode: "content", results: 7, tookUs: 42, roundTripMs: 3.5, error: "boom")
            ])
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

    @Test func reopenedLogCountsTheLinesAlreadyThere() throws {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        try FileManager.default.createDirectory(at: s.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let a = SearchLog(file: s.file, cap: 3)
        for i in 0..<5 { a.append(entry("old\(i)"), at: Date()) }
        let lines = { try String(contentsOf: s.file, encoding: .utf8).split(separator: "\n").count }
        // A new instance starts from the 5 lines on disk: one more reaches 2x cap
        // (no rewrite yet), the next goes over it and compacts.
        let b = SearchLog(file: s.file, cap: 3)
        b.append(entry("new0"), at: Date())
        #expect(try lines() == 6)
        b.append(entry("new1"), at: Date())
        #expect(try lines() == 3)
        #expect(b.entries().map(\.query) == ["old4", "new0", "new1"])
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

    @Test func concurrentAppendsAcrossCompactionStayWithinBounds() async throws {
        let s = sandbox(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let cap = 10
        let log = SearchLog(file: s.file, cap: cap)
        await withTaskGroup(of: Void.self) { g in
            for t in 0..<4 { g.addTask { for i in 0..<40 { log.append(self.entry("t\(t)-\(i)"), at: Date()) } } }
        }
        let got = log.entries().map(\.query)
        #expect(got.count == cap)
        #expect(Set(got).count == cap, "no record duplicated by a compaction")
        for t in 0..<4 {
            let mine = got.filter { $0.hasPrefix("t\(t)-") }.map { Int($0.split(separator: "-")[1])! }
            #expect(mine == mine.sorted(), "per-thread order holds across compaction")
        }
        #expect(try String(contentsOf: s.file, encoding: .utf8).split(separator: "\n").count <= 2 * cap)
    }
}

@Suite struct SearchLogPermissionTests {
    func mode(_ url: URL) -> Int {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
    func excluded(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup ?? false
    }
    func entry(_ q: String) -> SearchModel.LogEntry {
        SearchModel.LogEntry(query: q, mode: .names, resultCount: 0, tookUs: nil, roundTripMs: 0, error: nil)
    }

    @Test func folderIs0700AndFileIs0600AndBothSkipBackup() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fsk-logperm-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("logs/searches.jsonl")
        let log = SearchLog(file: file)
        log.append(entry("a"), at: Date())
        #expect(mode(file.deletingLastPathComponent()) == 0o700)
        #expect(mode(file) == 0o600)
        #expect(excluded(file.deletingLastPathComponent()))
        #expect(excluded(file))
    }

    @Test func compactKeepsTheFilePrivate() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fsk-logperm-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("searches.jsonl")
        let log = SearchLog(file: file, cap: 2)
        for i in 0..<6 { log.append(entry("q\(i)"), at: Date()) }  // 5 > 2*cap lines: compacted
        #expect(log.entries().map(\.query) == ["q4", "q5"])
        #expect(mode(file) == 0o600)
        #expect(excluded(file))
    }

    /// Securing touches the folder and file attributes several times: only on the first append, after a create or
    /// a compact, never on every append.
    @Test func securesOnCreateNotOnEveryAppend() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fsk-logperm-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("searches.jsonl")
        let log = SearchLog(file: file)
        log.append(entry("a"), at: Date())
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
        log.append(entry("b"), at: Date())
        #expect(mode(file) == 0o640, "a plain append leaves the attributes alone")
        try FileManager.default.removeItem(at: file)
        log.append(entry("c"), at: Date())
        #expect(mode(file) == 0o600 && excluded(file), "a recreated file is secured again")
        log.clear()
        log.append(entry("d"), at: Date())
        #expect(mode(file) == 0o600 && log.entries().map(\.query) == ["d"])
    }

    @Test func anExistingLooseFolderAndFileAreTightened() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fsk-logperm-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let file = dir.appendingPathComponent("searches.jsonl")
        FileManager.default.createFile(atPath: file.path, contents: Data(), attributes: [.posixPermissions: 0o644])
        SearchLog(file: file).append(entry("a"), at: Date())
        #expect(mode(dir) == 0o700)
        #expect(mode(file) == 0o600)
    }
}
