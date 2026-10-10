import Foundation

/// What the search UI needs from a daemon; ``DaemonClient`` in the app, a fake in tests.
///
/// Every method throws ``DaemonError``.
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
    private var nextId = 0

    /// Creates a client; it connects lazily on the first call.
    ///
    /// - Parameters:
    ///   - socketPath: The daemon's Unix socket.
    ///   - timeout: Seconds one round trip may take before it fails with ``DaemonError/timeout``.
    public init(socketPath: String = DaemonClient.defaultSocketPath, timeout: TimeInterval = 5) {
        socket = LineSocket(path: socketPath, timeout: timeout)
    }

    private func call<T: Decodable & Sendable>(_ req: Request, as: T.Type) async throws -> T {
        let cancelled = CancelFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
                queue.async { [self] in
                    // A call cancelled while queued is skipped without touching the socket.
                    if cancelled.isSet { cont.resume(throwing: CancellationError()); return }
                    nextId += 1
                    let id = nextId
                    do {
                        cont.resume(
                            returning: try decodeReply(try socket.roundTrip(req.json(id: id), accepts: { replyIsFor(id, $0) }), as: T.self))
                    } catch { cont.resume(throwing: error) }
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

/// Just the `id` of a reply, so a reply can be matched to its request before it is fully decoded.
private struct ReplyId: Decodable {
    let id: Int?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        // A non-integer id is kept as "not ours" (-1 never matches: ids start at 1).
        id = (try? c.decode(Int.self, forKey: .id)) ?? ((try? c.decodeNil(forKey: .id)) == false ? -1 : nil)
    }
    private enum Key: String, CodingKey { case id }
}

/// Whether a reply line answers request `id`. The daemon echoes the request's id (null
/// if the request had none), so a line carrying a different id is a stale leftover.
/// A line with no id, a null id, or no readable JSON object is accepted: the decode
/// step then reports it properly instead of it being silently dropped.
func replyIsFor(_ id: Int, _ line: Data) -> Bool {
    guard let r = try? JSONDecoder().decode(ReplyId.self, from: line), let got = r.id else { return true }
    return got == id
}

/// A thread-safe one-way flag, set by the cancellation handler and read on the queue.
private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
