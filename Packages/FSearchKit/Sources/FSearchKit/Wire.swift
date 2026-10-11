import Foundation

/// How the daemon reads a content pattern; the raw value is the wire name.
public enum GrepMode: String, Sendable {
    /// Plain text.
    case literal
    /// A regular expression.
    case regex
    /// A symbol definition.
    case symbol
}

/// One request to the daemon. Name search is the default op.
public enum Request: Sendable {
    /// Search file names. `limit` is left out of the JSON when `q` has its
    /// own `limit:` word, which the daemon would otherwise override.
    case search(q: String, limit: Int)
    /// Search inside files; `budgetMs` caps the daemon's time.
    case grep(q: String, pattern: String, mode: GrepMode, budgetMs: Int)
    /// Ask for the index state.
    case status
    /// Ask whether the daemon is alive.
    case ping
    /// Compact and save the index soon (the daemon answers "scheduled").
    case save

    /// One JSON line, without the newline.
    ///
    /// Keys are sorted so the output is stable.
    ///
    /// - Parameter id: The request id; the daemon echoes it in the reply.
    public func json(id: Int) -> Data {
        var o: [String: Any] = ["id": id]
        switch self {
        case let .search(q, limit):
            o["q"] = q
            // The daemon applies JSON fields after `q`: a JSON limit would override a typed `limit:`.
            if !QuerySplit.hasLimitWord(q) { o["limit"] = limit }
        case let .grep(q, pattern, mode, budget):
            o["op"] = "grep"; o["q"] = q; o["pattern"] = pattern; o["mode"] = mode.rawValue; o["budget_ms"] = budget
        case .status: o["op"] = "status"
        case .ping: o["op"] = "ping"
        case .save: o["op"] = "save"
        }
        return try! JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])
    }
}

/// A file the daemon found by name.
public struct Hit: Decodable, Equatable, Sendable {
    /// The absolute path.
    public let path: String
    /// `file`, `dir` or `link`.
    public let kind: String
    /// Size in bytes.
    public let size: UInt64
    /// Modification time, seconds since the Unix epoch.
    public let mtime: UInt32
    /// The match score; higher ranks first.
    public let score: Int32
    /// Creates a hit (used by tests and previews).
    public init(path: String, kind: String, size: UInt64, mtime: UInt32, score: Int32) {
        (self.path, self.kind, self.size, self.mtime, self.score) = (path, kind, size, mtime, score)
    }
}

/// The daemon's answer to a name search.
public struct SearchReply: Decodable, Equatable, Sendable {
    /// The daemon's time in microseconds.
    public let tookUs: UInt64
    /// The hits, best first.
    public let hits: [Hit]
    /// Creates a reply (used by tests and previews).
    public init(tookUs: UInt64, hits: [Hit]) { (self.tookUs, self.hits) = (tookUs, hits) }

    private enum CodingKeys: String, CodingKey { case tookUs, hits, files }
    /// Decodes a name-search reply.
    ///
    /// - Throws: ``DaemonError/badReply(_:)`` when the daemon answered with content-search lines instead.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A grep:/regex:/sym: word in the query makes the daemon answer with lines.
        if !c.contains(.hits) && c.contains(.files) {
            throw DaemonError.badReply("got a content-search reply where file names were expected")
        }
        (tookUs, hits) = (try c.decode(UInt64.self, forKey: .tookUs), try c.decode([Hit].self, forKey: .hits))
    }
}

/// One matching line inside a file.
public struct Match: Decodable, Equatable, Sendable {
    /// The 1-based line number.
    public let line: Int
    /// The line's text.
    public let text: String
    /// Creates a match (used by tests and previews).
    public init(line: Int, text: String) { (self.line, self.text) = (line, text) }
}

/// The matching lines of one file.
public struct FileMatches: Decodable, Equatable, Sendable {
    /// The file's path.
    public let path: String
    /// Its matching lines, in file order.
    public let matches: [Match]
}

/// The daemon's answer to a content search.
public struct GrepReply: Decodable, Equatable, Sendable {
    /// The daemon's time in microseconds.
    public let tookUs: UInt64
    /// Which source served the answer, such as `index`.
    public let source: String
    /// Files considered after the filters.
    public let candidates: Int
    /// Of those, how many were read.
    public let read: Int
    /// False when the time budget ended the search early, so more matches may exist.
    public let complete: Bool
    /// The files with matches.
    public let files: [FileMatches]
}

/// The daemon's index and permission state, as shown in Index Details.
public struct DaemonStatus: Decodable, Equatable, Sendable {
    /// Index entry counts as the daemon reports them: `entries` (all), `dirs`, and the pending `overlay` and `removed` changes.
    public let entries, dirs, overlay, removed: Int
    /// The last file-system event the index has applied.
    public let eventId: UInt64
    /// Index size in bytes, and the content index's document, segment, byte and pending-file counts.
    public let indexBytes, contentDocs, contentSegments, contentBytes, contentPending: Int
    /// Whether the daemon can read protected folders, and whether it owns the index (as opposed to following another daemon's).
    public let fullDiskAccess, owner: Bool

    private enum CodingKeys: String, CodingKey {
        case entries, dirs, overlay, removed, eventId, indexBytes, contentDocs, contentSegments, contentBytes, contentPending,
            fullDiskAccess, owner
    }

    /// Only `entries` is required. Older daemons lack newer fields (`owner`
    /// before fsearch 9560a09), which default to values that raise no warning:
    /// a daemon from before followers existed is the owner, and an unknown
    /// Full Disk Access state isn't reported as off.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ k: CodingKeys) throws -> Int { try c.decodeIfPresent(Int.self, forKey: k) ?? 0 }
        entries = try c.decode(Int.self, forKey: .entries)
        (dirs, overlay, removed) = (try int(.dirs), try int(.overlay), try int(.removed))
        eventId = try c.decodeIfPresent(UInt64.self, forKey: .eventId) ?? 0
        (indexBytes, contentDocs, contentSegments) = (try int(.indexBytes), try int(.contentDocs), try int(.contentSegments))
        (contentBytes, contentPending) = (try int(.contentBytes), try int(.contentPending))
        fullDiskAccess = try c.decodeIfPresent(Bool.self, forKey: .fullDiskAccess) ?? true
        owner = try c.decodeIfPresent(Bool.self, forKey: .owner) ?? true
    }
}

/// Why a daemon call failed. Its `description` is user-facing text.
public enum DaemonError: Error, Equatable, Sendable, LocalizedError, CustomStringConvertible {
    /// The first index isn't built yet (the daemon says "indexing ...").
    case indexing(String)
    /// Any other error the daemon reports, e.g. a bad regex or filter.
    case daemon(String)
    /// The socket can't be reached or was dropped.
    case disconnected
    /// The daemon didn't answer within the client's timeout.
    case timeout
    /// The reply wasn't the expected shape; the payload says what was wrong.
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
    /// The same text as ``description``, for `LocalizedError`.
    public var errorDescription: String? { description }
}

/// The `ok`/`error` fields every reply has.
private struct Envelope: Decodable { let ok: Bool; let error: String? }

extension DaemonClient {
    /// Decode one reply line, turning `{"ok": false, "error": ...}` into a DaemonError.
    ///
    /// An error beginning "indexing" becomes ``DaemonError/indexing(_:)``; any other becomes `.daemon`.
    ///
    /// - Parameters:
    ///   - line: One reply, without the newline.
    ///   - as: The type to decode (snake_case keys are converted).
    /// - Throws: ``DaemonError``; `.badReply` carries a short description (an unparseable line is cut to 200 characters).
    public static func decodeReply<T: Decodable>(_ line: Data, as: T.Type) throws -> T {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        guard let env = try? dec.decode(Envelope.self, from: line) else {
            throw DaemonError.badReply(String(decoding: line.prefix(200), as: UTF8.self))
        }
        if !env.ok {
            let msg = env.error ?? "error"
            throw msg.hasPrefix("indexing") ? DaemonError.indexing(msg) : DaemonError.daemon(msg)
        }
        do { return try dec.decode(T.self, from: line) } catch let e as DaemonError { throw e } catch let e as DecodingError {
            throw DaemonError.badReply(describe(e))
        } catch { throw DaemonError.badReply(String(describing: error)) }
    }
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
