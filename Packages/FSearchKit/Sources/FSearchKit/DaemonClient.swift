import Foundation

/// What the search UI needs from a daemon (a fake in tests).
public protocol SearchBackend: Sendable {
    func search(_ q: String, limit: Int) async throws -> SearchReply
    func grep(q: String, pattern: String, mode: GrepMode) async throws -> GrepReply
    func status() async throws -> DaemonStatus
    func ping() async throws
}

/// One connection to the fsearch daemon. Requests go out one at a time on a
/// serial queue: the daemon answers a connection in order, so replies never
/// cross between callers.
public final class DaemonClient: SearchBackend, @unchecked Sendable {
    public static var defaultSocketPath: String {
        NSHomeDirectory() + "/Library/Application Support/FSearch/fsearch.sock"
    }

    private let socket: LineSocket
    private let queue = DispatchQueue(label: "fsearch.client")
    private var nextId = 0

    public init(socketPath: String = DaemonClient.defaultSocketPath, timeout: TimeInterval = 5) {
        socket = LineSocket(path: socketPath, timeout: timeout)
    }

    private func call<T: Decodable & Sendable>(_ req: Request, as: T.Type) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                nextId += 1
                do { cont.resume(returning: try decodeReply(try socket.roundTrip(req.json(id: nextId)), as: T.self)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    public func search(_ q: String, limit: Int) async throws -> SearchReply {
        try await call(.search(q: q, limit: limit), as: SearchReply.self)
    }

    public func grep(q: String, pattern: String, mode: GrepMode) async throws -> GrepReply {
        try await call(.grep(q: q, pattern: pattern, mode: mode, budgetMs: 250), as: GrepReply.self)
    }

    public func status() async throws -> DaemonStatus {
        try await call(.status, as: DaemonStatus.self)
    }

    private struct Pong: Decodable, Sendable {}
    public func ping() async throws { _ = try await call(.ping, as: Pong.self) }

    /// Ask the daemon to compact and save its index (debug mode's "Save Now").
    public func save() async throws { _ = try await call(.save, as: Pong.self) }
}
