import Darwin
import Foundation

/// A blocking, newline-framed Unix-socket connection. Not thread-safe: the
/// owner serializes calls.
///
/// It dials lazily and keeps the connection between calls; any failure closes it.
final class LineSocket {
    /// Reject runaway replies rather than growing the receive buffer without bound.
    static let defaultMaxLineBytes = 64 * 1024 * 1024

    /// Thin wrapper over blocking socket syscalls so tests can inject EINTR/EAGAIN/poll errors.
    struct IO {
        var write: (Int32, UnsafeRawPointer, Int) -> Int = { Darwin.write($0, $1, $2) }
        var poll: (UnsafeMutablePointer<pollfd>, nfds_t, Int32) -> Int32 = { Darwin.poll($0, $1, $2) }
        var read: (Int32, UnsafeMutableRawPointer, Int) -> Int = { Darwin.read($0, $1, $2) }

        static var live: IO { IO() }
    }

    private var fd: Int32 = -1
    private var buffer = Data()
    private var chunk: [UInt8] = []
    let path: String
    let timeout: TimeInterval
    /// The only uid whose socket is trusted: ours, unless a test says otherwise.
    let expectedPeerUid: uid_t
    let maxLineBytes: Int
    let io: IO
    /// Names the peer of each new connection (see ``PeerIdentifier``); nil skips it.
    let identifyPeer: ((Int32) -> SocketHolder?)?
    /// Who the open connection's peer is, nil when not connected, not identified, or its token was unreadable.
    private(set) var peer: SocketHolder?

    init(
        path: String, timeout: TimeInterval, expectedPeerUid: uid_t = getuid(),
        maxLineBytes: Int = LineSocket.defaultMaxLineBytes, io: IO = .live,
        identifyPeer: ((Int32) -> SocketHolder?)? = nil
    ) {
        (self.path, self.timeout, self.expectedPeerUid, self.maxLineBytes, self.io) = (path, timeout, expectedPeerUid, maxLineBytes, io)
        self.identifyPeer = identifyPeer
    }
    deinit { close() }

    /// Closes the connection and drops any buffered bytes, so the next call dials again.
    func close() {
        if fd >= 0 { Darwin.close(fd) }
        fd = -1
        peer = nil
        buffer.removeAll()
    }

    private func connectIfNeeded() throws {
        if fd >= 0 { return }
        guard timeout.isFinite && timeout > 0 else { throw DaemonError.timeout }
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { throw DaemonError.disconnected }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        // sun_path is a fixed 104-byte buffer on macOS (NUL included); a longer path or embedded NUL can't be addressed.
        let fits = !path.utf8.contains(0) && path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path)
        guard fits else { Darwin.close(s); throw DaemonError.disconnected }
        withUnsafeMutableBytes(of: &addr.sun_path) { p in
            _ = path.withCString { strncpy(p.baseAddress!.assumingMemoryBound(to: CChar.self), $0, p.count - 1) }
        }
        // Receive and send time out after `timeout`, so a hung daemon can't block the caller; read() then fails with EAGAIN.
        // Clamp to a kernel-valid positive timeval so tiny values never turn into {0, 0} (infinite) and huge ones never trap.
        let clamped = min(timeout, 86_400 * 30)
        let sec = Int(clamped)
        var usec = Int32(((clamped - Double(sec)) * 1_000_000).rounded(.towardZero))
        if sec == 0 && usec == 0 { usec = 1 }
        var tv = timeval(tv_sec: sec, tv_usec: usec)
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        // Writing to a closed peer should fail with EPIPE, not kill the app with SIGPIPE.
        var one: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let r = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, len) } }
        guard r == 0 else { Darwin.close(s); throw DaemonError.disconnected }
        // A socket another user serves (a planted one) is never sent a query.
        var uid: uid_t = 0, gid: gid_t = 0
        guard peerIsTrusted(peerUid: getpeereid(s, &uid, &gid) == 0 ? uid : nil, expected: expectedPeerUid) else {
            Darwin.close(s); throw DaemonError.disconnected
        }
        // Who we talk to, from the kernel's record of this connection's peer, not from socket.lock.
        // An unknown same-user daemon (the CLI's) is still used; it is just never taken for ours.
        peer = identifyPeer?(s)
        fd = s
    }

    /// Send one line and read one line back. A connection that was already open
    /// and fails with `.disconnected` (the daemon restarted or dropped it) is
    /// re-dialled once and the line resent. Timeouts are not retried, and a fresh
    /// dial is never retried.
    ///
    /// `accepts` judges each line read: a rejected one (a stale reply) is dropped and
    /// the next line is read, all within one `timeout` deadline. A call that only ever
    /// sees rejected lines fails with `.timeout` and closes the connection.
    func roundTrip(_ line: Data, accepts: (Data) -> Bool = { _ in true }) throws -> Data {
        let reused = fd >= 0
        do {
            return try exchange(line, accepts)
        } catch DaemonError.disconnected where reused {
            return try exchange(line, accepts)
        }
    }

    /// One attempt. Any failure closes the connection, so the next attempt dials again.
    private func exchange(_ line: Data, _ accepts: (Data) -> Bool) throws -> Data {
        do {
            guard timeout.isFinite && timeout > 0 else { throw DaemonError.timeout }
            let deadline = ContinuousClock.now + .seconds(min(timeout, 86_400 * 30))
            try connectIfNeeded()
            var out = line
            out.append(UInt8(ascii: "\n"))
            try writeAll(out, deadline: deadline)
            while true {
                let reply = try readLine(deadline: deadline)
                if accepts(reply) { return reply }
                guard ContinuousClock.now < deadline else { throw DaemonError.timeout }
            }
        } catch {
            close()
            throw error
        }
    }

    /// Writes every byte, retrying partial writes and EINTR, and maps send timeouts to `.timeout`.
    private func writeAll(_ data: Data, deadline: ContinuousClock.Instant) throws {
        var offset = 0
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            while offset < data.count {
                let n = io.write(fd, base.advanced(by: offset), data.count - offset)
                if n > 0 {
                    offset += n
                    if offset < data.count && ContinuousClock.now >= deadline { throw DaemonError.timeout }
                    continue
                }
                if n < 0 && errno == EINTR {
                    if ContinuousClock.now >= deadline { throw DaemonError.timeout }
                    continue
                }
                if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { throw DaemonError.timeout }
                throw DaemonError.disconnected
            }
        }
    }

    /// Returns the next buffered line, reading from the socket as needed within `deadline`.
    /// Bytes after the newline stay buffered for the next call.
    private func readLine(deadline: ContinuousClock.Instant) throws -> Data {
        if chunk.isEmpty { chunk = [UInt8](repeating: 0, count: 64 * 1024) }
        var scanned = 0
        while true {
            guard ContinuousClock.now < deadline else { throw DaemonError.timeout }
            let from = buffer.index(buffer.startIndex, offsetBy: scanned)
            if let nl = buffer[from...].firstIndex(of: UInt8(ascii: "\n")) {
                if nl - buffer.startIndex > maxLineBytes { throw DaemonError.badReply("reply line too large") }
                let line = Data(buffer[buffer.startIndex..<nl])
                buffer.removeSubrange(buffer.startIndex...nl)
                if buffer.isEmpty { buffer.removeAll(keepingCapacity: true) }
                return line
            }
            if buffer.count > maxLineBytes { throw DaemonError.badReply("reply line too large") }
            scanned = buffer.count
            let ms = Self.remainingMilliseconds(ContinuousClock.now.duration(to: deadline))
            guard ms > 0 else { throw DaemonError.timeout }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = io.poll(&pfd, 1, ms)
            if ready == 0 { continue }
            if ready < 0 {
                if errno == EINTR { continue }
                throw DaemonError.disconnected
            }
            guard ContinuousClock.now < deadline else { throw DaemonError.timeout }
            if pfd.revents & Int16(POLLNVAL) != 0 { throw DaemonError.disconnected }
            guard pfd.revents & Int16(POLLIN | POLLHUP | POLLERR) != 0 else { continue }
            let n = io.read(fd, &chunk, chunk.count)
            if n > 0 {
                buffer.append(contentsOf: chunk[0..<n])
                continue
            }
            if n < 0 && errno == EINTR { continue }
            if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                if ContinuousClock.now >= deadline { throw DaemonError.timeout }
                continue
            }
            throw DaemonError.disconnected
        }
    }

    static func remainingMilliseconds(_ d: Duration) -> Int32 {
        let (s, a) = d.components
        if s < 0 || (s == 0 && a <= 0) { return 0 }
        let msFromSec = s > Int64(Int32.max / 1000) ? Int64(Int32.max) : s * 1000
        let msFromAtto = (a + 999_999_999_999_999) / 1_000_000_000_000_000
        return Int32(min(Int64(Int32.max), msFromSec + msFromAtto))
    }
}

/// The daemon on the other end runs as the expected user (nil: unknown).
func peerIsTrusted(peerUid: uid_t?, expected: uid_t) -> Bool { peerUid == expected }
