import Foundation
import Synchronization

/// What the search UI needs from a daemon; ``DaemonClient`` in the app, a fake in tests.
///
/// Every method throws ``DaemonError`` (or `CancellationError` if cancelled before reaching the socket).
public protocol SearchBackend: Sendable {
    /// Searches file names.
    ///
    /// - Parameters:
    ///   - q: The query, filters included.
    ///   - limit: The most hits to return; a `limit:` word in `q` overrides it.
    /// - Returns: The ranked hits.
    func search(_ q: String, limit: Int) async throws -> SearchReply
    /// Searches inside files.
    ///
    /// - Parameters:
    ///   - q: The filters that pick the files to search.
    ///   - pattern: What to look for.
    ///   - mode: How `pattern` is read.
    /// - Returns: The matching lines, grouped by file.
    func grep(q: String, pattern: String, mode: GrepMode) async throws -> GrepReply
    /// Reports the daemon's index and permission state.
    func status() async throws -> DaemonStatus
    /// Succeeds when the daemon answers.
    func ping() async throws
}

/// One connection to the fsearch daemon. Requests go out one at a time on a
/// serial queue: the daemon answers a connection in order, so replies never
/// cross between callers.
///
/// - A call cancelled while it waits in the queue never touches the socket; one already
///   on the wire finishes, since the reply must be read to keep the connection in step.
/// - A connection that was open and drops (the daemon restarted) is re-dialled and the
///   request resent once; a fresh dial or a timeout is not retried.
/// - Each reply must carry the id of the request; lines with another id are stale
///   leftovers and are skipped.
/// - `timeout` bounds one round trip, and the connection is closed after any failure.
///
/// The class is `@unchecked Sendable` because all mutable state is touched only on its serial queue.
public final class DaemonClient: SearchBackend, @unchecked Sendable {
    /// The daemon's socket in the user's Application Support folder.
    public static var defaultSocketPath: String {
        NSHomeDirectory() + "/Library/Application Support/FSearch/fsearch.sock"
    }

    private let socket: LineSocket
    private let queue = DispatchQueue(label: "fsearch.client")
    private let decoder = DaemonClient.makeDecoder()
    private var nextId = 0
    private let connectedPeer = Mutex<SocketHolder?>(nil)

    /// Who the daemon on the open connection is, by its code signature: set when the
    /// connection opens (with an `identifyPeer`), nil once it closes or when unknown.
    public var peer: SocketHolder? { connectedPeer.withLock { $0 } }

    /// Creates a client; it connects lazily on the first call.
    ///
    /// - Parameters:
    ///   - socketPath: The daemon's Unix socket.
    ///   - timeout: Seconds one round trip may take before it fails with ``DaemonError/timeout``.
    ///   - expectedPeerUid: The only user whose socket is trusted: ours (tests vary it). A socket
    ///     another user serves is never sent a query.
    ///   - identifyPeer: Names each new connection's peer for ``peer``; nil skips it. An
    ///     unidentified or unknown peer is still talked to.
    public init(
        socketPath: String = DaemonClient.defaultSocketPath, timeout: TimeInterval = 5, expectedPeerUid: uid_t = getuid(),
        identifyPeer: PeerIdentifier? = nil
    ) {
        socket = LineSocket(
            path: socketPath, timeout: timeout, expectedPeerUid: expectedPeerUid, identifyPeer: identifyPeer.map { $0.identify(socket:) })
    }

    private func call<T: Decodable & Sendable>(_ req: Request, as: T.Type) async throws -> T {
        try Task.checkCancellation()
        let cancelled = CancelFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
                queue.async { [self] in
                    // A call cancelled while queued is skipped without touching the socket.
                    if cancelled.isSet { cont.resume(throwing: CancellationError()); return }
                    nextId += 1
                    let id = nextId
                    let result = Result { try socket.roundTrip(req.json(id: id), accepts: { replyIsFor(id, $0) }) }
                    let peer = socket.peer
                    connectedPeer.withLock { $0 = peer }
                    cont.resume(with: result.flatMap { line in Result { try Self.decodeReply(line, as: T.self, using: decoder) } })
                }
            }
        } onCancel: {
            cancelled.set()
        }
    }

    /// Searches file names.
    ///
    /// - Throws: ``DaemonError``: `.indexing` while the first index is built, `.disconnected` or `.timeout` when the daemon can't be reached or is slow, `.daemon` for an error it reports (a bad filter), `.badReply` for a reply of the wrong shape, including a content-search reply.
    public func search(_ q: String, limit: Int) async throws -> SearchReply {
        try await call(.search(q: q, limit: limit), as: SearchReply.self)
    }

    /// Searches inside files, giving the daemon a 250 ms budget.
    ///
    /// The daemon returns what it found when the budget runs out; ``GrepReply/complete`` says whether that was everything.
    ///
    /// - Throws: ``DaemonError``, as for ``search(_:limit:)``.
    public func grep(q: String, pattern: String, mode: GrepMode) async throws -> GrepReply {
        try await call(.grep(q: q, pattern: pattern, mode: mode, budgetMs: 250), as: GrepReply.self)
    }

    /// Reads the daemon's status.
    ///
    /// - Throws: ``DaemonError``.
    public func status() async throws -> DaemonStatus {
        try await call(.status, as: DaemonStatus.self)
    }

    /// The empty reply to `ping` and `save`; only the `ok` envelope matters.
    private struct Pong: Decodable, Sendable {}
    /// Checks that the daemon answers.
    ///
    /// - Throws: ``DaemonError``.
    public func ping() async throws { _ = try await call(.ping, as: Pong.self) }

    /// Asks the daemon to compact and save its index (debug mode's "Save Now").
    ///
    /// The daemon replies once the save is scheduled, not when it finishes.
    ///
    /// - Throws: ``DaemonError``.
    public func save() async throws { _ = try await call(.save, as: Pong.self) }
}

/// Whether a reply line answers request `id`. The daemon echoes the request's id (null
/// if the request had none), so a line carrying a different id is a stale leftover.
/// A line with no id, a null id, or no readable JSON object is accepted: the decode
/// step then reports it properly instead of it being silently dropped.
func replyIsFor(_ id: Int, _ line: Data) -> Bool {
    switch scanTopLevelReplyId(line) {
    case let .int(got): got == id
    case .nonInt: false
    case .missingOrNull, .invalidJSON: true
    }
}

private enum ReplyIdScan {
    case int(Int)
    case nonInt
    case missingOrNull
    case invalidJSON
}

/// Zero-allocation scanner for a JSON object's top-level `"id"` field, avoiding
/// a full JSONDecoder pass just to match request ids.
private func scanTopLevelReplyId(_ line: Data) -> ReplyIdScan {
    line.withUnsafeBytes { raw -> ReplyIdScan in
        let b = raw.bindMemory(to: UInt8.self)
        let n = b.count
        var i = 0

        func skipWS() {
            while i < n {
                switch b[i] {
                case 0x20, 0x09, 0x0A, 0x0D: i += 1
                default: return
                }
            }
        }

        func skipString() -> Bool {
            guard i < n, b[i] == 0x22 else { return false }
            i += 1
            while i < n {
                let c = b[i]
                i += 1
                if c == 0x22 { return true }
                if c == 0x5C {
                    guard i < n else { return false }
                    i += 1
                }
            }
            return false
        }

        func skipValue() -> Bool {
            skipWS()
            guard i < n else { return false }
            switch b[i] {
            case 0x22: return skipString()
            case 0x7B, 0x5B:  // '{' or '['
                var depth = 0
                while i < n {
                    switch b[i] {
                    case 0x22:
                        guard skipString() else { return false }
                        continue
                    case 0x7B, 0x5B: depth += 1
                    case 0x7D, 0x5D:
                        depth -= 1
                        if depth == 0 {
                            i += 1
                            return true
                        }
                    default: break
                    }
                    i += 1
                }
                return false
            default:
                let start = i
                while i < n {
                    switch b[i] {
                    case 0x20, 0x09, 0x0A, 0x0D, 0x2C, 0x7D, 0x5D: return i > start
                    default: i += 1
                    }
                }
                return i > start
            }
        }

        func parseIdValue() -> ReplyIdScan {
            skipWS()
            guard i < n else { return .invalidJSON }
            // null
            if i + 4 <= n, b[i] == 0x6E, b[i + 1] == 0x75, b[i + 2] == 0x6C, b[i + 3] == 0x6C {
                let end = i + 4
                if end == n || b[end] == 0x2C || b[end] == 0x7D || b[end] == 0x20 || b[end] == 0x09 || b[end] == 0x0A || b[end] == 0x0D {
                    return .missingOrNull
                }
            }
            var j = i
            var neg = false
            if b[j] == 0x2D {
                neg = true
                j += 1
            }
            let digitsStart = j
            var value = 0
            var overflow = false
            while j < n, b[j] >= 0x30, b[j] <= 0x39 {
                let d = Int(b[j] - 0x30)
                let (m, mo) = value.multipliedReportingOverflow(by: 10)
                let (a, ao) = neg ? m.subtractingReportingOverflow(d) : m.addingReportingOverflow(d)
                if mo || ao { overflow = true } else { value = a }
                j += 1
            }
            if j > digitsStart, !overflow {
                if j == n || b[j] == 0x2C || b[j] == 0x7D || b[j] == 0x20 || b[j] == 0x09 || b[j] == 0x0A || b[j] == 0x0D {
                    return .int(value)
                }
            }
            return .nonInt
        }

        skipWS()
        guard i < n, b[i] == 0x7B else { return .invalidJSON }
        i += 1
        skipWS()
        if i < n, b[i] == 0x7D { return .missingOrNull }

        while i < n {
            guard b[i] == 0x22 else { return .invalidJSON }
            let keyStart = i + 1
            guard skipString() else { return .invalidJSON }
            let keyEnd = i - 1
            let isIdKey = keyEnd - keyStart == 2 && b[keyStart] == 0x69 && b[keyStart + 1] == 0x64
            skipWS()
            guard i < n, b[i] == 0x3A else { return .invalidJSON }
            i += 1
            if isIdKey { return parseIdValue() }
            guard skipValue() else { return .invalidJSON }
            skipWS()
            guard i < n else { return .invalidJSON }
            if b[i] == 0x2C {
                i += 1
                skipWS()
                continue
            }
            return b[i] == 0x7D ? .missingOrNull : .invalidJSON
        }
        return .invalidJSON
    }
}

/// A thread-safe one-way flag, set by the cancellation handler and read on the queue.
private final class CancelFlag: Sendable {
    private let state = Mutex(false)
    func set() { state.withLock { $0 = true } }
    var isSet: Bool { state.withLock { $0 } }
}
