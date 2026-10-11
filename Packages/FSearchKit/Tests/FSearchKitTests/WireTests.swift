import Foundation
import Testing

@testable import FSearchKit

@Suite struct WireTests {
    func obj(_ d: Data) -> [String: Any] { try! JSONSerialization.jsonObject(with: d) as! [String: Any] }

    @Test func searchRequest() {
        let o = obj(Request.search(q: "main.rs", limit: 50).json(id: 7))
        #expect(o["q"] as? String == "main.rs")
        #expect(o["limit"] as? Int == 50)
        #expect(o["id"] as? Int == 7)
        #expect(o["op"] == nil, "search is the default op")
    }

    @Test func grepRequest() {
        let o = obj(Request.grep(q: "ext:rs", pattern: "hello world", mode: .literal, budgetMs: 250).json(id: 1))
        #expect(o["op"] as? String == "grep")
        #expect(o["pattern"] as? String == "hello world")
        #expect(o["mode"] as? String == "literal")
        #expect(o["q"] as? String == "ext:rs")
        #expect(o["budget_ms"] as? Int == 250)
    }

    @Test func statusPingSave() {
        #expect(obj(Request.status.json(id: 2))["op"] as? String == "status")
        #expect(obj(Request.ping.json(id: 3))["op"] as? String == "ping")
        #expect(obj(Request.save.json(id: 4))["op"] as? String == "save")
    }

    @Test func lineHasNoNewline() {
        #expect(!Request.ping.json(id: 1).contains(UInt8(ascii: "\n")))
    }

    @Test func decodesSearch() throws {
        let line =
            #"{"ok":true,"took_us":372,"hits":[{"path":"/Users/me/a b/🏡 x.pdf","kind":"file","size":19,"mtime":1791515321,"score":-22}],"id":4}"#
        let r = try DaemonClient.decodeReply(Data(line.utf8), as: SearchReply.self)
        #expect(r.tookUs == 372)
        #expect(r.hits == [Hit(path: "/Users/me/a b/🏡 x.pdf", kind: "file", size: 19, mtime: 1791515321, score: -22)])
    }

    @Test func decodesGrep() throws {
        let line =
            #"{"ok":true,"took_us":900,"source":"index","candidates":3,"read":3,"complete":true,"indexing":0,"files":[{"path":"/p/f.txt","matches":[{"line":2,"text":"a heron needle"}]}],"id":1}"#
        let r = try DaemonClient.decodeReply(Data(line.utf8), as: GrepReply.self)
        #expect(r.files.first?.matches == [Match(line: 2, text: "a heron needle")])
        #expect(r.source == "index" && r.complete)
    }

    @Test func decodesStatus() throws {
        let line =
            #"{"content_bytes":644805248,"content_docs":583120,"content_pending":0,"content_segments":39,"dirs":1055573,"entries":6646939,"event_id":1304740247,"full_disk_access":true,"id":null,"index_bytes":232654400,"ok":true,"overlay":0,"owner":true,"removed":0}"#
        let s = try DaemonClient.decodeReply(Data(line.utf8), as: DaemonStatus.self)
        #expect(s.entries == 6646939 && s.fullDiskAccess && s.owner && s.eventId == 1304740247)
    }

    /// A CLI daemon from before fsearch 9560a09 has no `owner` (and older ones
    /// lack more): status still decodes, with defaults that raise no warning.
    @Test func decodesAnOlderDaemonsStatus() throws {
        let line = #"{"ok":true,"entries":12,"dirs":3,"overlay":0,"removed":0,"event_id":9}"#
        let s = try DaemonClient.decodeReply(Data(line.utf8), as: DaemonStatus.self)
        #expect(s.entries == 12 && s.dirs == 3 && s.eventId == 9)
        #expect(s.owner && s.fullDiskAccess)
        #expect(s.indexBytes == 0 && s.contentDocs == 0 && s.contentSegments == 0 && s.contentBytes == 0 && s.contentPending == 0)
        let bare = try DaemonClient.decodeReply(Data(#"{"ok":true,"entries":1}"#.utf8), as: DaemonStatus.self)
        #expect(bare.entries == 1 && bare.dirs == 0 && bare.eventId == 0)
        // Not a status at all: still an error.
        #expect(throws: DaemonError.self) { try DaemonClient.decodeReply(Data(#"{"ok":true}"#.utf8), as: DaemonStatus.self) }
    }

    @Test func errorsMapToDaemonError() {
        #expect(throws: DaemonError.indexing("indexing (first run scans the whole disk, ~20s)")) {
            try DaemonClient.decodeReply(
                Data(#"{"ok":false,"error":"indexing (first run scans the whole disk, ~20s)"}"#.utf8), as: DaemonStatus.self)
        }
        #expect(throws: DaemonError.daemon("unknown type dir")) {
            try DaemonClient.decodeReply(Data(#"{"ok":false,"error":"unknown type dir"}"#.utf8), as: SearchReply.self)
        }
        #expect(throws: DaemonError.badReply("not json")) { try DaemonClient.decodeReply(Data("not json".utf8), as: SearchReply.self) }
    }
}

@Suite struct WireReplyShapeTests {
    @Test func grepReplyToANameSearchIsAClearError() {
        let line = #"{"ok":true,"took_us":900,"source":"index","candidates":3,"read":3,"complete":true,"files":[]}"#
        #expect(throws: DaemonError.badReply("got a content-search reply where file names were expected")) {
            try DaemonClient.decodeReply(Data(line.utf8), as: SearchReply.self)
        }
    }
    @Test func missingFieldNamesTheField() {
        do {
            _ = try DaemonClient.decodeReply(Data(#"{"ok":true,"took_us":1}"#.utf8), as: SearchReply.self)
            Issue.record("decoded a reply with no hits")
        } catch let DaemonError.badReply(msg) {
            #expect(msg == #"reply has no "hits""#)
        } catch { Issue.record("unexpected \(error)") }
    }
}
