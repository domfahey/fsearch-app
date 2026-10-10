import Darwin
import FSearchKit
import Foundation

/// A minimal in-process daemon: answers every request line with one canned
/// reply line, so a DaemonClient round trip measures only client + socket cost.
final class CannedServer: @unchecked Sendable {
    let path: String
    private let reply: Data
    private var listener: Int32 = -1

    init(dir: URL, reply: Data) throws {
        path = dir.appendingPathComponent("canned.sock").path
        var r = reply
        r.append(UInt8(ascii: "\n"))
        self.reply = r
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BenchError("socket() failed") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd); throw BenchError("socket path too long: \(path)")
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { p in
            _ = path.withCString { strncpy(p.baseAddress!.assumingMemoryBound(to: CChar.self), $0, p.count - 1) }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let ok = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }
        guard ok == 0, listen(fd, 8) == 0 else { close(fd); throw BenchError("bind/listen failed on \(path)") }
        listener = fd
        let reply = self.reply
        Thread.detachNewThread {
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 { return }
                var one: Int32 = 1
                setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
                Thread.detachNewThread { CannedServer.serve(c, reply) }
            }
        }
    }

    /// Answers each request line with the canned reply carrying that request's
    /// id: DaemonClient drops a reply whose id isn't the one it asked for.
    private static func serve(_ c: Int32, _ reply: Data) {
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        var line: [UInt8] = []
        while true {
            let n = read(c, &chunk, chunk.count)
            if n <= 0 { close(c); return }
            for i in 0..<n {
                guard chunk[i] == UInt8(ascii: "\n") else { line.append(chunk[i]); continue }
                let out = withID(requestID(line), reply)
                line.removeAll(keepingCapacity: true)
                let sent = out.withUnsafeBytes { write(c, $0.baseAddress, out.count) }
                if sent != out.count { close(c); return }
            }
        }
    }

    /// The integer after `"id":` in a request line, if any.
    private static func requestID(_ line: [UInt8]) -> Int? {
        let key = Array(#""id":"#.utf8)
        guard line.count > key.count else { return nil }
        for i in 0...(line.count - key.count) where Array(line[i..<(i + key.count)]) == key {
            var j = i + key.count, v = 0, any = false
            while j < line.count, line[j] >= 48, line[j] <= 57 { v = v * 10 + Int(line[j] - 48); j += 1; any = true }
            return any ? v : nil
        }
        return nil
    }

    /// `reply` (one line, newline-terminated, ending in `"id":<n>}`) with `id` swapped in.
    private static func withID(_ id: Int?, _ reply: Data) -> Data {
        guard let id, let s = String(data: reply, encoding: .utf8), let r = s.range(of: #""id":"#, options: .backwards) else {
            return reply
        }
        return Data((s[..<r.lowerBound] + #""id":\#(id)}"# + "\n").utf8)
    }

    func stop() {
        if listener >= 0 { shutdown(listener, SHUT_RDWR); close(listener); listener = -1 }
        unlink(path)
    }

    deinit { stop() }
}

struct BenchError: Error, CustomStringConvertible {
    let description: String
    init(_ s: String) { description = s }
}

/// The run could not finish because the machine or daemon was too slow: a
/// result of "inconclusive", not a benchmark failure.
struct Inconclusive: Error, CustomStringConvertible {
    let description: String
    init(_ s: String) { description = s }
}

/// Client round trip against the canned server, and SearchModel latest-wins
/// overhead against a stub backend.
@MainActor func benchClient(_ b: Bench, work: URL) async throws {
    let c = b.config
    if c.wants("client.search50") || c.wants("client.grep50") {
        let s = try CannedServer(dir: work, reply: Fixtures.searchReplyLine(hits: 50))
        defer { s.stop() }
        let client = DaemonClient(socketPath: s.path, timeout: 15)
        try await b.measureAsync("client.search50", group: .inproc, warmup: 50, samples: 400) {
            blackHole(try await client.search("heron lattice", limit: 50))
        }
        let g = try CannedServer(
            dir: work.appendingPathComponent("g", isDirectory: true).creating(), reply: Fixtures.grepReplyLine(files: 50))
        defer { g.stop() }
        let gclient = DaemonClient(socketPath: g.path, timeout: 15)
        try await b.measureAsync("client.grep50", group: .inproc, warmup: 50, samples: 400) {
            blackHole(try await gclient.grep(q: "", pattern: "heron", mode: .literal))
        }
    }

    // 100 rapid keystrokes: each sets the query and starts a refresh; only the
    // last may publish. Measures the whole burst until every refresh returns.
    let stub = StubBackend()
    let model = SearchModel(names: stub, content: stub)
    var published = 0
    model.onSearched = { _ in published += 1 }
    let queries = (0..<100).map { "heron lattice \($0)" }
    try await b.measureAsync(
        "model.refresh.burst100", group: .inproc, warmup: 5, samples: 60,
        info: { ["published_last_run": "\(published)"] }
    ) {
        published = 0
        var tasks: [Task<Void, Never>] = []
        tasks.reserveCapacity(queries.count)
        for q in queries {
            model.query = q
            tasks.append(Task { @MainActor in await model.refresh() })
        }
        for t in tasks { await t.value }
        guard model.items.count == 50 else { throw BenchError("refresh burst ended without results") }
    }
    try await b.measureAsync("model.refresh.single", group: .inproc, warmup: 20, samples: 400) {
        model.query = "heron lattice"
        await model.refresh()
    }
}

extension URL {
    func creating() throws -> URL {
        try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        return self
    }
}
