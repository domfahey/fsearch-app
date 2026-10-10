import Darwin
import Foundation

/// A scripted daemon on a temp Unix socket.
final class FakeDaemon: @unchecked Sendable {
    let path: String
    private let reply: @Sendable ([String: Any]) -> [String: Any]?
    private let lock = NSLock()
    // All fields below are guarded by `lock`.
    private var listener: Int32 = -1
    private var owned: (dev: dev_t, ino: ino_t)?  // identity of our socket file
    private var conns: [Int32] = []                // accepted fds still open
    private var stopped = false
    private var _requests: [[String: Any]] = []

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
        withUnsafeMutableBytes(of: &addr.sun_path) { p in _ = path.withCString { strncpy(p.baseAddress!.assumingMemoryBound(to: CChar.self), $0, p.count - 1) } }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = bind(fd, $0, len) } }
        listen(fd, 8)
        var st = stat()
        if lstat(path, &st) == 0 { owned = (st.st_dev, st.st_ino) }
        lock.lock(); listener = fd; lock.unlock()
        Thread.detachNewThread { [self] in
            while true {
                let c = accept(fd, nil, nil)
                lock.lock()
                if c < 0 || stopped {
                    if c >= 0 { close(c) }
                    lock.unlock()
                    return
                }
                var one: Int32 = 1
                setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                conns.append(c)
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
    /// Idempotent. A stopped daemon never closes an fd or unlinks a path it no longer owns.
    func stop() {
        lock.lock(); defer { lock.unlock() }
        if stopped { return }
        stopped = true
        if listener >= 0 {
            shutdown(listener, SHUT_RDWR)  // wakes the blocked accept()
            close(listener)
            listener = -1
        }
        for c in conns { shutdown(c, SHUT_RDWR) }  // their serving threads close them
        var st = stat()
        if let o = owned, lstat(path, &st) == 0, st.st_dev == o.dev, st.st_ino == o.ino {
            unlink(path)
        }
    }

    deinit { stop() }
}
