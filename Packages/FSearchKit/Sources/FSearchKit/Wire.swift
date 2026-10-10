import Foundation

public enum GrepMode: String, Sendable { case literal, regex, symbol }

/// One request to the daemon. Name search is the default op.
public enum Request: Sendable {
    case search(q: String, limit: Int)
    case grep(q: String, pattern: String, mode: GrepMode, budgetMs: Int)
    case status
    case ping
    /// Compact and save the index soon (the daemon answers "scheduled").
    case save

    /// One JSON line, without the newline.
    public func json(id: Int) -> Data {
        var o: [String: Any] = ["id": id]
        switch self {
        case let .search(q, limit): o["q"] = q; o["limit"] = limit
        case let .grep(q, pattern, mode, budget):
            o["op"] = "grep"; o["q"] = q; o["pattern"] = pattern; o["mode"] = mode.rawValue; o["budget_ms"] = budget
        case .status: o["op"] = "status"
        case .ping: o["op"] = "ping"
        case .save: o["op"] = "save"
        }
        return try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])
    }
}

public struct Hit: Decodable, Equatable, Sendable {
    public let path: String
    public let kind: String
    public let size: UInt64
    public let mtime: UInt32
    public let score: Int32
    public init(path: String, kind: String, size: UInt64, mtime: UInt32, score: Int32) {
        (self.path, self.kind, self.size, self.mtime, self.score) = (path, kind, size, mtime, score)
    }
}

public struct SearchReply: Decodable, Equatable, Sendable {
    public let tookUs: UInt64
    public let hits: [Hit]
    public init(tookUs: UInt64, hits: [Hit]) { (self.tookUs, self.hits) = (tookUs, hits) }

    private enum CodingKeys: String, CodingKey { case tookUs, hits, files }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A grep:/regex:/sym: word in the query makes the daemon answer with lines.
        if !c.contains(.hits) && c.contains(.files) {
            throw DaemonError.badReply("got a content-search reply where file names were expected")
        }
        (tookUs, hits) = (try c.decode(UInt64.self, forKey: .tookUs), try c.decode([Hit].self, forKey: .hits))
    }
}

public struct Match: Decodable, Equatable, Sendable {
    public let line: Int
    public let text: String
    public init(line: Int, text: String) { (self.line, self.text) = (line, text) }
}

public struct FileMatches: Decodable, Equatable, Sendable {
    public let path: String
    public let matches: [Match]
}

public struct GrepReply: Decodable, Equatable, Sendable {
    public let tookUs: UInt64
    public let source: String
    public let candidates: Int
    public let read: Int
    public let complete: Bool
    public let files: [FileMatches]
}

public struct DaemonStatus: Decodable, Equatable, Sendable {
    public let entries, dirs, overlay, removed: Int
    public let eventId: UInt64
    public let indexBytes, contentDocs, contentSegments, contentBytes, contentPending: Int
    public let fullDiskAccess, owner: Bool
}

public enum DaemonError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    /// The first index isn't built yet (the daemon says "indexing ...").
    case indexing(String)
    /// Any other error the daemon reports, e.g. a bad regex or filter.
    case daemon(String)
    case disconnected
    case timeout
    case badReply(String)

    /// Short text for the user (and the search log), not the Swift case name.
    public var description: String {
        switch self {
        case .indexing: "The search index is still being built"
        case let .daemon(msg): msg.isEmpty ? "The search daemon reported an error" : msg
        case .disconnected: "Can't reach the search daemon"
        case .timeout: "The search daemon didn't answer in time"
        case let .badReply(detail): "Unexpected reply from the search daemon: \(detail)"
        }
    }
    public var errorDescription: String? { description }
}

private struct Envelope: Decodable { let ok: Bool; let error: String? }

/// Decode one reply line, turning `{"ok": false, "error": ...}` into a DaemonError.
public func decodeReply<T: Decodable>(_ line: Data, as: T.Type) throws -> T {
    let dec = JSONDecoder()
    dec.keyDecodingStrategy = .convertFromSnakeCase
    guard let env = try? dec.decode(Envelope.self, from: line) else {
        throw DaemonError.badReply(String(decoding: line.prefix(200), as: UTF8.self))
    }
    if !env.ok {
        let msg = env.error ?? "error"
        throw msg.hasPrefix("indexing") ? DaemonError.indexing(msg) : DaemonError.daemon(msg)
    }
    do { return try dec.decode(T.self, from: line) }
    catch let e as DaemonError { throw e }
    catch let e as DecodingError { throw DaemonError.badReply(describe(e)) }
    catch { throw DaemonError.badReply(String(describing: error)) }
}

/// One short line for a reply that didn't have the expected shape.
private func describe(_ e: DecodingError) -> String {
    func at(_ c: DecodingError.Context) -> String {
        let path = c.codingPath.map { $0.intValue.map(String.init) ?? wireName($0.stringValue) }.joined(separator: ".")
        return path.isEmpty ? "" : " at \(path)"
    }
    switch e {
    case let .keyNotFound(key, c): return "reply has no \"\(wireName(key.stringValue))\"" + at(c)
    case let .typeMismatch(_, c), let .valueNotFound(_, c): return "unexpected value in reply" + at(c)
    case let .dataCorrupted(c): return "unreadable reply" + at(c)
    @unknown default: return "unreadable reply"
    }
}

/// The daemon's JSON key for a Swift property name (`tookUs` -> `took_us`).
private func wireName(_ swift: String) -> String {
    var out = ""
    for ch in swift {
        if ch.isUppercase { out += "_" + ch.lowercased() } else { out.append(ch) }
    }
    return out
}
