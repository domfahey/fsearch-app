import Darwin
import Foundation

/// A scripted daemon on a temp Unix socket.
final class FakeDaemon: @unchecked Sendable {
    let path: String
    private var fd: Int32 = -1
    private let reply: @Sendable ([String: Any]) -> [String: Any]?
    private(set) var requests: [[String: Any]] = []
    private let lock = NSLock()
    private var conns: [Int32] = []

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
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { p in _ = path.withCString { strncpy(p.baseAddress!.assumingMemoryBound(to: CChar.self), $0, p.count - 1) } }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = bind(fd, $0, len) } }
        listen(fd, 8)
        let listener = fd
        Thread.detachNewThread { [self] in
            while true {
                let c = accept(listener, nil, nil)
                if c < 0 { return }
                lock.lock(); conns.append(c); lock.unlock()
                Thread.detachNewThread { self.serve(c) }
            }
        }
    }

    private func serve(_ c: Int32) {
        var buf = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(c, &chunk, chunk.count)
            if n <= 0 { close(c); return }
            buf.append(contentsOf: chunk[0..<n])
            while let nl = buf.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buf[buf.startIndex..<nl]
                buf.removeSubrange(buf.startIndex...nl)
                let req = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] ?? [:]
                lock.lock(); requests.append(req); lock.unlock()
                guard var out = reply(req) else { continue }
                out["id"] = req["id"]
                var data = try! JSONSerialization.data(withJSONObject: out)
                data.append(UInt8(ascii: "\n"))
                _ = data.withUnsafeBytes { write(c, $0.baseAddress, data.count) }
            }
        }
    }

    /// Stop accepting and remove the socket file (a "crashed" daemon).
    func stop() {
        close(fd); unlink(path)
        lock.lock(); let open = conns; conns = []; lock.unlock()
        for c in open { shutdown(c, SHUT_RDWR) }
    }
    deinit { stop() }
}
