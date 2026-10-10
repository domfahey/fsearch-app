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
}
