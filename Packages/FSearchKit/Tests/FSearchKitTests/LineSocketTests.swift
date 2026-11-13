import Darwin
import Foundation
import Testing

@testable import FSearchKit

/// A raw Unix-socket server on a temp path. `handler` runs on its own thread
/// for each accepted connection and owns the fd (it must close it).
///
/// Only the accept thread closes the listening fd, and `stop()` waits for it,
/// so the fd number can't be reused by another test while `accept` still
/// holds it. On macOS `shutdown()` doesn't wake an `accept` blocked on a
/// listener (it fails with ENOTCONN), so `stop()` wakes it by dialling in.
final class RawServer: @unchecked Sendable {
    let path: String
    private let lock = NSLock()
    private var _accepted = 0, stopping = false
    private let exited = DispatchSemaphore(value: 0)
    var accepted: Int { lock.withLock { _accepted } }

    init(path: String? = nil, handler: @escaping @Sendable (Int32, Int) -> Void) {
        let path = path ?? NSTemporaryDirectory() + "fsk-raw-\(UUID().uuidString.prefix(8)).sock"
        self.path = path
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        precondition(fd >= 0, "socket: errno \(errno)")
        precondition(path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path), "socket path too long: \(path)")
        precondition(Self.withAddress(path) { bind(fd, $0, $1) } == 0, "bind \(path): errno \(errno)")
        precondition(listen(fd, 8) == 0, "listen: errno \(errno)")
        // The thread holds self until stop(), which every test calls (there is no deinit).
        Thread.detachNewThread { [self] in
            defer { close(fd); exited.signal() }
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 {
                    if errno == EINTR || errno == ECONNABORTED { continue }
                    return
                }
                let n = lock.withLock { () -> Int? in
                    if stopping { return nil }
                    _accepted += 1
                    return _accepted
                }
                guard let n else { close(c); return }  // stop()'s wake-up dial
                Thread.detachNewThread { handler(c, n) }
            }
        }
    }

    /// Idempotent. Returns once the accept thread has closed the listener.
    func stop() {
        let first = lock.withLock { () -> Bool in
            defer { stopping = true }; return !stopping
        }
        guard first else { return }
        // Wake the blocked accept with a connection of our own.
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        if s >= 0 {
            _ = Self.withAddress(path) { connect(s, $0, $1) }
            close(s)
        }
        // Bounded, so a wake-up that never lands fails loudly instead of hanging the run.
        precondition(exited.wait(timeout: .now() + 5) == .success, "RawServer accept thread did not exit")
        unlink(path)
    }

    private static func withAddress(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> Int32) -> Int32 {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { p in
            _ = path.withCString { strncpy(p.baseAddress!.assumingMemoryBound(to: CChar.self), $0, p.count - 1) }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, len) } }
    }

    /// Read up to and including the next newline; false on EOF.
    static func readLine(_ fd: Int32) -> Bool {
        var b: UInt8 = 0
        while true {
            let n = read(fd, &b, 1)
            if n <= 0 { return false }
            if b == UInt8(ascii: "\n") { return true }
        }
    }

    static func send(_ fd: Int32, _ s: String) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))  // a gone client is not a crash
        let d = Array(s.utf8)
        var off = 0
        while off < d.count {
            let n = d.withUnsafeBytes { write(fd, $0.baseAddress! + off, d.count - off) }
            if n <= 0 { return }
            off += n
        }
    }
}

@Suite struct LineSocketTests {
    func req(_ s: String = "{}") -> Data { Data(s.utf8) }

    @Test func connectingToAMissingSocketIsDisconnected() {
        let s = LineSocket(path: NSTemporaryDirectory() + "fsk-nope-\(UUID().uuidString.prefix(8)).sock", timeout: 1)
        #expect(throws: DaemonError.disconnected) { try s.roundTrip(req()) }
        #expect(throws: DaemonError.disconnected) { try s.roundTrip(req()) }
    }

    @Test func aPathNobodyListensOnIsDisconnected() throws {
        // A regular file is not a socket.
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("fsk-notsock-\(UUID())")
        try Data("x".utf8).write(to: f)
        defer { try? FileManager.default.removeItem(at: f) }
        #expect(throws: DaemonError.disconnected) { try LineSocket(path: f.path, timeout: 1).roundTrip(req()) }
    }

    @Test func aPathTooLongForASocketAddressIsDisconnected() {
        let long = "/tmp/" + String(repeating: "a", count: 200) + ".sock"
        #expect(throws: DaemonError.disconnected) { try LineSocket(path: long, timeout: 1).roundTrip(req()) }
        // sun_path holds 104 bytes including the NUL. A server listens at the
        // longest path that fits (103 bytes); dialling one byte more must not
        // be silently truncated onto it.
        let limit = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        let dir = NSTemporaryDirectory() + "fsk-"
        let fits = dir + String(repeating: "b", count: limit - 1 - dir.utf8.count)
        #expect(fits.utf8.count == limit - 1)
        let srv = RawServer(path: fits) { fd, _ in
            while RawServer.readLine(fd) { RawServer.send(fd, "{}\n") }
            close(fd)
        }
        defer { srv.stop() }
        #expect(throws: Never.self) { try LineSocket(path: fits, timeout: 1).roundTrip(req()) }
        #expect(throws: DaemonError.disconnected) { try LineSocket(path: fits + "x", timeout: 1).roundTrip(req()) }
        #expect(srv.accepted == 1, "only the dial that fits connected")
    }

    @Test func echoesOneLine() throws {
        let srv = RawServer { fd, _ in
            while RawServer.readLine(fd) { RawServer.send(fd, "{\"ok\":true}\n") }
            close(fd)
        }
        defer { srv.stop() }
        let s = LineSocket(path: srv.path, timeout: 2)
        #expect(String(decoding: try s.roundTrip(req()), as: UTF8.self) == "{\"ok\":true}")
        #expect(String(decoding: try s.roundTrip(req()), as: UTF8.self) == "{\"ok\":true}")
        #expect(srv.accepted == 1, "the connection is reused")
    }

    @Test func peerClosingMidLineIsDisconnectedWithoutRetryOnAFreshDial() throws {
        let srv = RawServer { fd, _ in
            _ = RawServer.readLine(fd)
            RawServer.send(fd, "{\"ok\":tr")  // no newline, then hang up
            close(fd)
        }
        defer { srv.stop() }
        let s = LineSocket(path: srv.path, timeout: 2)
        #expect(throws: DaemonError.disconnected) { try s.roundTrip(req()) }
        #expect(srv.accepted == 1, "a fresh dial is never retried")
    }

    @Test func peerClosingWithoutAnyReplyIsDisconnected() {
        let srv = RawServer { fd, _ in
            _ = RawServer.readLine(fd); close(fd)
        }
        defer { srv.stop() }
        #expect(throws: DaemonError.disconnected) { try LineSocket(path: srv.path, timeout: 2).roundTrip(req()) }
    }

    @Test func partialLineAcrossWritesIsAssembled() throws {
        let srv = RawServer { fd, _ in
            _ = RawServer.readLine(fd)
            RawServer.send(fd, "{\"ok\"")
            RawServer.send(fd, ":tr")
            RawServer.send(fd, "ue}\n")
            close(fd)
        }
        defer { srv.stop() }
        let line = try LineSocket(path: srv.path, timeout: 2).roundTrip(req())
        #expect(String(decoding: line, as: UTF8.self) == "{\"ok\":true}")
    }

    @Test func dripReplyCannotExceedTotalTimeout() {
        let srv = RawServer { fd, _ in
            _ = RawServer.readLine(fd)
            RawServer.send(fd, "part")
            Thread.sleep(forTimeInterval: 0.12)
            RawServer.send(fd, "ial")
            Thread.sleep(forTimeInterval: 0.12)
            RawServer.send(fd, "\n")
            close(fd)
        }
        defer { srv.stop() }
        let socket = LineSocket(path: srv.path, timeout: 0.18)
        #expect(throws: DaemonError.timeout) { try socket.roundTrip(req()) }
        #expect(srv.accepted == 1)
    }

    @Test func staleCompleteReplyDoesNotResetTimeout() {
        let srv = RawServer { fd, _ in
            _ = RawServer.readLine(fd)
            Thread.sleep(forTimeInterval: 0.22)
            RawServer.send(fd, "stale\n")
            Thread.sleep(forTimeInterval: 0.3)
            close(fd)
        }
        defer { srv.stop() }
        let socket = LineSocket(path: srv.path, timeout: 0.3)
        let started = DispatchTime.now().uptimeNanoseconds
        #expect(throws: DaemonError.timeout) {
            try socket.roundTrip(req(), accepts: { _ in false })
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        #expect(elapsed < 0.45, "a stale complete line shares the original deadline")
    }

    @Test func oversizedLineBiggerThanTheReadChunkIsReturnedWhole() throws {
        let big = String(repeating: "x", count: 600_000)
        let srv = RawServer { fd, _ in
            _ = RawServer.readLine(fd)
            RawServer.send(fd, big + "\n")
            close(fd)
        }
        defer { srv.stop() }
        let line = try LineSocket(path: srv.path, timeout: 5).roundTrip(req())
        #expect(line.count == big.utf8.count)
    }

    @Test func largeRequestIsSentWhole() throws {
        let big = String(repeating: "q", count: 300_000)
        let got = Locked<Int>(0)
        let srv = RawServer { fd, _ in
            var n = 0
            var b = [UInt8](repeating: 0, count: 65536)
            outer: while true {
                let r = read(fd, &b, b.count)
                if r <= 0 { break }
                for i in 0..<r { if b[i] == UInt8(ascii: "\n") { n += i; break outer } }
                n += r
            }
            got.set(n)
            RawServer.send(fd, "done\n")
            close(fd)
        }
        defer { srv.stop() }
        _ = try LineSocket(path: srv.path, timeout: 5).roundTrip(req(big))
        #expect(got.get() == big.utf8.count)
    }

    @Test func emptyReplyLineIsAnEmptyData() throws {
        let srv = RawServer { fd, _ in
            _ = RawServer.readLine(fd); RawServer.send(fd, "\n"); close(fd)
        }
        defer { srv.stop() }
        #expect(try LineSocket(path: srv.path, timeout: 2).roundTrip(req()).isEmpty)
    }

    @Test func silentPeerTimesOutAndIsNotRetried() {
        let srv = RawServer { fd, _ in
            _ = RawServer.readLine(fd)
            // Hold the connection open until the client gives up, but hang up
            // after 5 s so a broken timeout fails the test instead of hanging it.
            var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            _ = poll(&p, 1, 5000)
            close(fd)
        }
        defer { srv.stop() }
        let t0 = Date()
        #expect(throws: DaemonError.timeout) { try LineSocket(path: srv.path, timeout: 0.3).roundTrip(req()) }
        #expect(Date().timeIntervalSince(t0) >= 0.25, "the sub-second part of the timeout is honoured")
        #expect(srv.accepted == 1)
    }

    @Test func aDroppedConnectionIsRedialledOnce() throws {
        let srv = RawServer { fd, n in
            _ = RawServer.readLine(fd)
            RawServer.send(fd, "reply\(n)\n")
            if n == 1 { close(fd); return }  // first connection: answer once, then hang up
            while RawServer.readLine(fd) { RawServer.send(fd, "reply\(n)\n") }
            close(fd)
        }
        defer { srv.stop() }
        let s = LineSocket(path: srv.path, timeout: 2)
        #expect(String(decoding: try s.roundTrip(req()), as: UTF8.self) == "reply1")
        // The server closed our reused connection; the retry dials again.
        #expect(String(decoding: try s.roundTrip(req()), as: UTF8.self) == "reply2")
        #expect(srv.accepted == 2)
    }

    @Test func reusedConnectionThatFailsAgainOnTheRetryGivesUp() throws {
        let srv = RawServer { fd, n in
            _ = RawServer.readLine(fd)
            if n == 1 { RawServer.send(fd, "ok\n") }
            close(fd)
        }
        defer { srv.stop() }
        let s = LineSocket(path: srv.path, timeout: 2)
        _ = try s.roundTrip(req())
        #expect(throws: DaemonError.disconnected) { try s.roundTrip(req()) }
        #expect(srv.accepted == 2, "the reused connection was redialled once, and only once")
    }

    @Test func closeIsIdempotentAndForcesAFreshDial() throws {
        let srv = RawServer { fd, _ in
            while RawServer.readLine(fd) { RawServer.send(fd, "a\n") }
            close(fd)
        }
        defer { srv.stop() }
        let s = LineSocket(path: srv.path, timeout: 2)
        s.close(); s.close()
        _ = try s.roundTrip(req())
        s.close()
        _ = try s.roundTrip(req())
        #expect(srv.accepted == 2)
    }

    @Test func closeDropsBufferedBytes() throws {
        // Two lines in one write: the second stays buffered. After close() it is gone.
        let srv = RawServer { fd, n in
            _ = RawServer.readLine(fd)
            RawServer.send(fd, n == 1 ? "one\nleftover\n" : "two\n")
            while RawServer.readLine(fd) { RawServer.send(fd, "again\n") }
            close(fd)
        }
        defer { srv.stop() }
        let s = LineSocket(path: srv.path, timeout: 2)
        #expect(String(decoding: try s.roundTrip(req()), as: UTF8.self) == "one")
        s.close()
        #expect(String(decoding: try s.roundTrip(req()), as: UTF8.self) == "two")
    }
}

final class Locked<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var v: T
    init(_ v: T) { self.v = v }
    func get() -> T { lock.withLock { v } }
    func set(_ x: T) { lock.withLock { v = x } }
}
