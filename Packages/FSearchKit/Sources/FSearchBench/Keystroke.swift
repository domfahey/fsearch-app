import FSearchKit
import Foundation

/// Canned daemon replies, shared by the decode and client benchmarks.
enum Fixtures {
    static func searchReplyLine(hits: Int = 50) -> Data {
        let hs = (0..<hits).map { i in
            #"{"path":"/Users/someone/Developer/project-\#(i % 7)/src/module\#(i)/heron_lattice_\#(i).swift","kind":"file","size":\#(1000 + i * 37),"mtime":\#(1_760_000_000 + i),"score":\#(900 - i)}"#
        }
        return Data(#"{"ok":true,"took_us":412,"hits":[\#(hs.joined(separator: ","))],"id":7}"#.utf8)
    }

    static func grepReplyLine(files: Int = 50, matchesPerFile: Int = 3) -> Data {
        let fs = (0..<files).map { i in
            let ms = (0..<matchesPerFile).map { j in
                #"{"line":\#(10 + j * 7),"text":"    let lattice = quantum.lattice(\#(i), \#(j)) // a heron needle in the haystack"}"#
            }
            return #"{"path":"/Users/someone/Developer/project/src/file\#(i).rs","matches":[\#(ms.joined(separator: ","))]}"#
        }
        return Data(#"{"ok":true,"took_us":1900,"source":"index","candidates":120,"read":120,"complete":true,"indexing":0,"files":[\#(fs.joined(separator: ","))],"id":8}"#.utf8)
    }
}

/// SearchModel.LogEntry has only a memberwise init internal to FSearchKit, so
/// the benchmark gets real entries by running a SearchModel against a stub
/// backend once and capturing what `onSearched` reports.
enum LogEntryFactory {
    nonisolated(unsafe) static var template: SearchModel.LogEntry?

    @MainActor static func prepare() async {
        let stub = StubBackend()
        let m = SearchModel(names: stub, content: stub)
        m.onSearched = { template = $0 }
        m.query = "heron lattice"
        await m.refresh()
    }
}

/// The per-keystroke pure paths.
@MainActor func benchKeystroke(_ b: Bench, work: URL) async {
    // QuerySplit
    let plain = "heron lattice needle"
    let filters = "heron lattice ext:rs,md in:~/Developer mtime:<7d size:>10kb"
    let quoted = #"in:"~/My Stuff" "exact phrase" heron ext:"swift" lattice"#
    b.measure("keystroke.split.plain") { blackHole(QuerySplit.split(plain)) }
    b.measure("keystroke.split.filters") { blackHole(QuerySplit.split(filters)) }
    b.measure("keystroke.split.quoted") { blackHole(QuerySplit.split(quoted)) }
    b.measure("keystroke.contentSearch") { blackHole(QuerySplit.contentSearch("src grep:heron ext:rs")) }

    // PanelRows: map every selectable row for a 50-result list.
    b.measure("keystroke.panelRows.50") {
        let rows = PanelRows(files: 50, query: plain, mode: .names)
        var acc = 0
        for i in 0..<rows.count {
            if case .result(let r)? = rows.row(at: i) { acc &+= r }
        }
        blackHole(acc)
    }

    // PanelKeys.reduce: a burst of navigation keys plus escape handling.
    let keys: [PanelKey] = [.down, .down, .down, .up, .cmdDigit(3), .enter, .cmdK, .escape, .backspaceOnEmpty, .escape]
    b.measure("keystroke.panelKeys.reduce10") {
        var s = PanelState(query: plain, mode: .content, selection: 0, count: 52, files: 50)
        var acc = 0
        for k in keys { if case .open(let i) = FSearchKit.reduce(&s, k) { acc &+= i } }
        blackHole(acc)
    }

    // decodeReply
    let sr = Fixtures.searchReplyLine(hits: 50)
    let gr = Fixtures.grepReplyLine(files: 50)
    b.measure("decode.search50") { blackHole(try? decodeReply(sr, as: SearchReply.self)) }
    b.measure("decode.grep50") { blackHole(try? decodeReply(gr, as: GrepReply.self)) }

    // SearchLog with a 10k-line file.
    await LogEntryFactory.prepare()
    let entry = LogEntryFactory.template!
    let logDir = work.appendingPathComponent("searchlog")
    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    let seed = logDir.appendingPathComponent("seed.jsonl")
    let live = logDir.appendingPathComponent("searches.jsonl")
    // Write 10k records through SearchLog itself, then copy that file before each sample.
    let w = SearchLog(file: seed, cap: 10_000)
    for i in 0..<10_000 { w.append(entry, at: Date(timeIntervalSince1970: 1_760_000_000 + Double(i))) }
    var log: SearchLog!
    func reset() {
        try? FileManager.default.removeItem(at: live)
        try? FileManager.default.copyItem(at: seed, to: live)
        log = SearchLog(file: live, cap: 10_000)
        log.append(entry, at: Date())   // seeds the line count; untimed
    }
    // File I/O (open, seek, write, close per append): other processes' disk
    // activity moves it more than CPU work, hence the wider tolerance.
    b.measure("searchlog.append.10k", ops: 50, tolerance: 0.50, setup: reset) { log.append(entry, at: Date()) }
    reset()
    let reader = SearchLog(file: live, cap: 10_000)
    b.measure("searchlog.entries.10k", ops: 1) { blackHole(reader.entries()) }

    // DebugFormat: the per-row formatters, and the filtered 10k-row log view.
    let rows = reader.entries()
    b.measure("debugformat.row") {
        blackHole(DebugFormat.daemonMs(412))
        blackHole(DebugFormat.roundTrip(1.53))
        blackHole(DebugFormat.bytes(123_456_789))
    }
    b.measure("debugformat.shown.10k", ops: 1) { blackHole(DebugFormat.shown(rows, filter: "LATTICE 99")) }
    try? FileManager.default.removeItem(at: logDir)
}

/// Answers instantly with a 50-hit reply (and a 50-file grep reply).
final class StubBackend: SearchBackend, @unchecked Sendable {
    let reply: SearchReply
    let grepReply: GrepReply
    init() {
        reply = try! decodeReply(Fixtures.searchReplyLine(), as: SearchReply.self)
        grepReply = try! decodeReply(Fixtures.grepReplyLine(), as: GrepReply.self)
    }
    func search(_ q: String, limit: Int) async throws -> SearchReply { reply }
    func grep(q: String, pattern: String, mode: GrepMode) async throws -> GrepReply { grepReply }
    func status() async throws -> DaemonStatus { throw DaemonError.disconnected }
    func ping() async throws {}
}
