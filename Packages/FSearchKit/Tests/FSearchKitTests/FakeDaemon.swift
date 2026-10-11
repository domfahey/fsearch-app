import Darwin
import Foundation

/// A scripted daemon on a temp Unix socket.
final class FakeDaemon: @unchecked Sendable {
    let path: String
    private let reply: @Sendable ([String: Any]) -> [String: Any]?
    private let lock = NSLock()
    // All fields below are guarded by `lock`.
    private var wake: Int32 = -1  // write end of the accept thread's wake pipe
    private var owned: (dev: dev_t, ino: ino_t)?  // identity of our socket file
    private var conns: [Int32] = []  // accepted fds still open
    private var stopped = false
    private var _requests: [[String: Any]] = []
    private var _accepted = 0

    /// Connections accepted so far (a reconnecting client shows up as more than one).
    var accepted: Int {
        lock.lock(); defer { lock.unlock() }
        return _accepted
    }

    var requests: [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    init(reply: @escaping @Sendable ([String: Any]) -> [String: Any]?) {
        path = NSTemporaryDirectory() + "fsk-\(UUID().uuidString.prefix(8)).sock"
        self.reply = reply
        start()
    }

    init(path: String, reply: @escaping @Sendable ([String: Any]) -> [String: Any]?) {
        self.path = path
        self.reply = reply
        start()
    }

    private func start() {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { p in
            _ = path.withCString { strncpy(p.baseAddress!.assumingMemoryBound(to: CChar.self), $0, p.count - 1) }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = bind(fd, $0, len) } }
        listen(fd, 8)
        var st = stat()
        if lstat(path, &st) == 0 { owned = (st.st_dev, st.st_ino) }
        // The accept thread owns `fd` and closes it itself. stop() must never close it:
        // the thread may not have reached accept() yet, and once the number is free the
        // next daemon's socket() can reuse it, so a stale thread would accept (and drop)
        // a connection meant for the new daemon. stop() closes the pipe's write end instead.
        var p: [Int32] = [-1, -1]
        pipe(&p)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)  // poll() then accept(): never block
        lock.lock(); wake = p[1]; lock.unlock()
        let wakeRead = p[0]
        Thread.detachNewThread { [self] in
            defer { close(fd); close(wakeRead) }
            var fds = [
                pollfd(fd: fd, events: Int16(POLLIN), revents: 0),
                pollfd(fd: wakeRead, events: Int16(POLLIN), revents: 0),
            ]
            while true {
                fds[0].revents = 0; fds[1].revents = 0
                if poll(&fds, 2, -1) < 0 { if errno == EINTR { continue }; return }
                if fds[1].revents != 0 { return }  // stop() closed the write end
                let c = accept(fd, nil, nil)
                if c < 0 { if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR || errno == ECONNABORTED { continue }; return }
                _ = fcntl(c, F_SETFL, fcntl(c, F_GETFL) & ~O_NONBLOCK)  // accepted fds inherit O_NONBLOCK on Darwin
                lock.lock()
                if stopped { close(c); lock.unlock(); return }
                var one: Int32 = 1
                setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                conns.append(c)
                _accepted += 1
                lock.unlock()
                Thread.detachNewThread { self.serve(c) }
            }
        }
    }

    private func serve(_ c: Int32) {
        var buf = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(c, &chunk, chunk.count)
            if n <= 0 { finish(c); return }
            buf.append(contentsOf: chunk[0..<n])
            while let nl = buf.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buf[buf.startIndex..<nl]
                buf.removeSubrange(buf.startIndex...nl)
                let req = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] ?? [:]
                lock.lock(); _requests.append(req); lock.unlock()
                guard var out = reply(req) else { continue }
                out["id"] = req["id"]
                var data = try! JSONSerialization.data(withJSONObject: out)
                data.append(UInt8(ascii: "\n"))
                _ = data.withUnsafeBytes { write(c, $0.baseAddress, data.count) }
            }
        }
    }

    /// Close one accepted connection. Only the serving thread closes its own fd,
    /// and it leaves `conns` in the same critical section, so no fd is closed twice.
    private func finish(_ c: Int32) {
        lock.lock()
        conns.removeAll { $0 == c }
        close(c)
        lock.unlock()
    }

    /// Stop accepting, drop open connections, and remove the socket file if it is still ours.
    /// Idempotent. A stopped daemon never closes an fd or unlinks a path it no longer owns,
    /// and its accept thread never touches a listener fd number that could belong to another daemon.
    func stop() {
        lock.lock(); defer { lock.unlock() }
        if stopped { return }
        stopped = true
        if wake >= 0 {
            close(wake)  // wakes the accept thread, which closes the listener itself
            wake = -1
        }
        for c in conns { shutdown(c, SHUT_RDWR) }  // their serving threads close them
        var st = stat()
        if let o = owned, lstat(path, &st) == 0, st.st_dev == o.dev, st.st_ino == o.ino {
            unlink(path)
        }
    }

    deinit { stop() }
}
