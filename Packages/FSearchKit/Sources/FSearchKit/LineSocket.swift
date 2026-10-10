import Darwin
import Foundation

/// A blocking, newline-framed Unix-socket connection. Not thread-safe: the
/// owner serializes calls.
///
/// It dials lazily and keeps the connection between calls; any failure closes it.
final class LineSocket {
    private var fd: Int32 = -1
    private var buffer = Data()
    let path: String
    let timeout: TimeInterval

    init(path: String, timeout: TimeInterval) { (self.path, self.timeout) = (path, timeout) }
    deinit { close() }

    /// Closes the connection and drops any buffered bytes, so the next call dials again.
    func close() {
        if fd >= 0 { Darwin.close(fd) }
        fd = -1
        buffer.removeAll()
    }

    private func connectIfNeeded() throws {
        if fd >= 0 { return }
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { throw DaemonError.disconnected }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        // sun_path is a fixed 104-byte buffer on macOS (NUL included); a longer path can't be addressed.
        let fits = path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path)
        guard fits else { Darwin.close(s); throw DaemonError.disconnected }
        withUnsafeMutableBytes(of: &addr.sun_path) { p in
            _ = path.withCString { strncpy(p.baseAddress!.assumingMemoryBound(to: CChar.self), $0, p.count - 1) }
        }
        // Receive and send time out after `timeout`, so a hung daemon can't block the caller; read() then fails with EAGAIN.
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        // Writing to a closed peer should fail with EPIPE, not kill the app with SIGPIPE.
        var one: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let r = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, len) } }
        guard r == 0 else { Darwin.close(s); throw DaemonError.disconnected }
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
            try connectIfNeeded()
            var out = line
            out.append(UInt8(ascii: "\n"))
            let sent = out.withUnsafeBytes { write(fd, $0.baseAddress, out.count) }
            guard sent == out.count else { throw DaemonError.disconnected }
            let deadline = Date().addingTimeInterval(timeout)
            while true {
                let reply = try readLine()
                if accepts(reply) { return reply }
                if Date() >= deadline { throw DaemonError.timeout }
            }
        } catch {
            close()
            throw error
        }
    }

    /// Returns the next buffered line, reading from the socket as needed. Bytes after the newline stay buffered for the next call.
    private func readLine() throws -> Data {
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            if let nl = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[buffer.startIndex..<nl]
                buffer.removeSubrange(buffer.startIndex...nl)
                return Data(line)
            }
            let n = read(fd, &chunk, chunk.count)
            if n > 0 { buffer.append(contentsOf: chunk[0..<n]); continue }
            if n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) { throw DaemonError.timeout }
            throw DaemonError.disconnected
        }
    }
}
