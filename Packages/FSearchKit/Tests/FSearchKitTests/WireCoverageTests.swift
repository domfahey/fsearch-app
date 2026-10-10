import Foundation
import Testing
@testable import FSearchKit

/// A Decodable whose decoding fails with an error that is neither a
/// DecodingError nor a DaemonError.
private struct Exploding: Decodable {
    init(from decoder: Decoder) throws { throw CocoaError(.fileReadUnknown) }
}

@Suite struct WireCoverageTests {
    func badReplyMessage<T: Decodable>(_ json: String, as: T.Type) -> String? {
        do { _ = try decodeReply(Data(json.utf8), as: T.self); return nil }
        catch let DaemonError.badReply(m) { return m }
        catch { return "other: \(error)" }
    }

    @Test func notOkWithoutAMessageIsAGenericDaemonError() {
        #expect(throws: DaemonError.daemon("error")) {
            try decodeReply(Data(#"{"ok":false}"#.utf8), as: SearchReply.self)
        }
    }

    @Test func indexingPrefixDecidesTheCase() {
        #expect(throws: DaemonError.indexing("indexing")) {
            try decodeReply(Data(#"{"ok":false,"error":"indexing"}"#.utf8), as: DaemonStatus.self)
        }
        // Only a prefix counts.
        #expect(throws: DaemonError.daemon("still indexing")) {
            try decodeReply(Data(#"{"ok":false,"error":"still indexing"}"#.utf8), as: DaemonStatus.self)
        }
        #expect(throws: DaemonError.daemon("")) {
            try decodeReply(Data(#"{"ok":false,"error":""}"#.utf8), as: DaemonStatus.self)
        }
    }

    @Test func okFalseWinsEvenWhenTheRestLooksValid() {
        let json = #"{"ok":false,"error":"nope","took_us":1,"hits":[]}"#
        #expect(throws: DaemonError.daemon("nope")) { try decodeReply(Data(json.utf8), as: SearchReply.self) }
    }

    @Test func notAnEnvelopeIsBadReplyWithTheText() {
        #expect(badReplyMessage("not json", as: SearchReply.self) == "not json")
        #expect(badReplyMessage("", as: SearchReply.self) == "")
        #expect(badReplyMessage("[1,2]", as: SearchReply.self) == "[1,2]")
        #expect(badReplyMessage(#"{"took_us":1}"#, as: SearchReply.self) == #"{"took_us":1}"#, "no ok field")
    }

    @Test func garbageIsCutAtTwoHundredBytes() {
        let long = String(repeating: "x", count: 500)
        #expect(badReplyMessage(long, as: SearchReply.self) == String(repeating: "x", count: 200))
    }

    @Test func wrongTypeNamesThePathIncludingArrayIndexes() {
        let json = #"{"ok":true,"took_us":1,"hits":[{"path":"/a","kind":"file","size":"big","mtime":1,"score":1}]}"#
        #expect(badReplyMessage(json, as: SearchReply.self) == "unexpected value in reply at hits.0.size")
    }

    @Test func nullWhereAValueIsNeeded() {
        let json = #"{"ok":true,"took_us":1,"hits":null}"#
        let m = badReplyMessage(json, as: SearchReply.self)
        #expect(m?.hasPrefix("unexpected value in reply") == true, "got \(m ?? "nil")")
        #expect(m?.hasSuffix(" at hits") == true)
    }

    @Test func numberOutOfRangeIsABadReply() {
        let json = #"{"ok":true,"took_us":1e40,"hits":[]}"#
        let m = badReplyMessage(json, as: SearchReply.self)
        #expect(m != nil && m?.hasPrefix("other") == false, "got \(m ?? "nil")")
    }

    @Test func missingNestedKeyNamesItsPath() {
        let json = #"{"ok":true,"took_us":1,"source":"i","candidates":1,"read":1,"complete":true,"files":[{"path":"/p"}]}"#
        #expect(badReplyMessage(json, as: GrepReply.self) == #"reply has no "matches" at files.0"#)
    }

    @Test func missingTopLevelKeyHasNoPathSuffix() {
        #expect(badReplyMessage(#"{"ok":true}"#, as: SearchReply.self) == #"reply has no "tookUs""#)
    }

    @Test func unrelatedDecoderErrorsBecomeBadReply() {
        let m = badReplyMessage(#"{"ok":true}"#, as: Exploding.self)
        #expect(m?.isEmpty == false && m?.hasPrefix("other") == false)
    }

    @Test func emptyOkObjectDecodesAsPong() throws {
        struct Pong: Decodable {}
        _ = try decodeReply(Data(#"{"ok":true,"id":1}"#.utf8), as: Pong.self)
    }

    @Test func snakeCaseKeysMapToCamelCase() throws {
        let s = try decodeReply(Data(#"{"ok":true,"took_us":5,"hits":[]}"#.utf8), as: SearchReply.self)
        #expect(s == SearchReply(tookUs: 5, hits: []))
    }

    @Test func requestJSONEscapesAndIsDeterministic() throws {
        let line = Request.grep(q: "a\"b", pattern: "x\ny", mode: .symbol, budgetMs: 1).json(id: 9)
        let o = try JSONSerialization.jsonObject(with: line) as! [String: Any]
        #expect(o["q"] as? String == "a\"b" && o["pattern"] as? String == "x\ny" && o["mode"] as? String == "symbol")
        #expect(!line.contains(UInt8(ascii: "\n")))
        #expect(Request.ping.json(id: 1) == Request.ping.json(id: 1))
        #expect(GrepMode(rawValue: "regex") == .regex)
    }

    @Test func daemonErrorEquality() {
        #expect(DaemonError.indexing("a") != DaemonError.daemon("a"))
        #expect(DaemonError.badReply("a") == DaemonError.badReply("a"))
        #expect(DaemonError.timeout != DaemonError.disconnected)
    }
}
