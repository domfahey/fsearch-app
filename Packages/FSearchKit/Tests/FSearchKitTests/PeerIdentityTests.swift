import Darwin
import Foundation
import Synchronization
import Testing

@testable import FSearchKit

/// The daemon is named by the kernel's audit token for the connected socket,
/// not by a pid a same-user process can write into socket.lock.
@Suite struct PeerIdentityTests {
    let bundle = "/Applications/FSearch.app"

    // MARK: pure classification

    /// A peer is a live process, so it is never `.none`; the path rules match socket.lock's.
    @Test func aPeerIsOursOnlyByTheHelperRules() {
        func peer(_ path: String?, signed: Bool = false, appSigned: Bool = true) -> SocketHolder {
            SocketHolder.classifyPeer(path: path, signedAsHelper: { signed }, appTeamSigned: { appSigned }, bundlePath: bundle)
        }
        #expect(peer(bundle + "/Contents/Helpers/fsearch") == .ours)
        #expect(peer(bundle + "/Contents/MacOS/FSearch", signed: true) == .other, "in the bundle, only the helper")
        #expect(peer("/opt/homebrew/bin/fsearch") == .other)
        #expect(peer("/Users/me/.Trash/FSearch.app/Contents/Helpers/fsearch", signed: true) == .ours)
        #expect(peer("/Users/me/.Trash/FSearch.app/Contents/Helpers/fsearch") == .other)
        #expect(peer("/tmp/x/FSearch.app/Contents/Helpers/fsearch", appSigned: false) == .ours, "a dev build's moved helper")
        #expect(peer(nil, signed: true) == .ours, "its file is gone but its signature is ours")
        #expect(peer(nil) == .none, "file gone, not signed as ours: unnamed, as socket.lock would say")
    }

    @Test func identifyingWithoutATokenGivesNothing() {
        var id = PeerIdentifier.stub(bundlePath: bundle)
        id.auditToken = { _ in nil }
        #expect(id.identify(socket: 3) == nil)
    }

    @Test func identifyingChecksTheTokensCode() {
        let token = Data([1, 2, 3])
        let asked = Mutex<[String]>([])
        var id = PeerIdentifier.stub(bundlePath: bundle)
        id.auditToken = { $0 == 7 ? token : nil }
        id.path = { $0 == token ? "/Users/me/.Trash/FSearch.app/Contents/Helpers/fsearch" : nil }
        id.satisfies = { t, req in
            asked.withLock { $0.append(req) }
            return t == token
        }
        #expect(id.identify(socket: 7) == .ours)
        #expect(asked.withLock { $0 } == [SocketHolder.helperRequirement])
        id.satisfies = { _, _ in false }
        #expect(id.identify(socket: 7) == .other)
        #expect(id.identify(socket: 8) == nil)
    }

    // MARK: ownership needs the peer and socket.lock to agree

    /// The peer can be stale (named when the control connection last answered) and socket.lock
    /// can be forged, so when they disagree the answer that does least wins: either can make the
    /// app leave a daemon alone, neither can make it manage one that isn't ours.
    @Test func theMoreCautiousOfPeerAndSocketLockWins() {
        #expect(DaemonPlan.holder(peer: .other, lock: { .ours }) == .other, "forged lock")
        #expect(DaemonPlan.holder(peer: .ours, lock: { .other }) == .other, "stale peer: another daemon took the socket")
        #expect(DaemonPlan.holder(peer: .ours, lock: { .none }) == .ours)
        #expect(DaemonPlan.holder(peer: SocketHolder.none, lock: { .ours }) == .ours)
        #expect(DaemonPlan.holder(peer: SocketHolder.none, lock: { .none }) == .none)
        #expect(DaemonPlan.holder(peer: nil, lock: { .ours }) == .ours)
        #expect(DaemonPlan.holder(peer: nil, lock: { .other }) == .other)
    }

    /// After an update deletes the old bundle, the old helper's file is gone. Unsigned (a dev
    /// build), it is unnamed either way, so it stays ours to restart.
    @Test func anOldHelperWhoseFileIsGoneStaysOurs() {
        let peer = SocketHolder.classifyPeer(path: nil, signedAsHelper: { false }, appTeamSigned: { false }, bundlePath: bundle)
        let lock = SocketHolder.classify(pid: 42, path: nil, signedAsHelper: false, appTeamSigned: false, bundlePath: bundle)
        #expect(DaemonPlan.owns(helperEnabled: true, holder: DaemonPlan.holder(peer: peer, lock: { lock })))
    }

    @Test func labelsThePeerForIndexDetails() {
        #expect(DebugFormat.peerLabel(.ours) == "FSearch helper (signature verified)")
        #expect(DebugFormat.peerLabel(.other) == "Other (unverified)")
        #expect(DebugFormat.peerLabel(SocketHolder.none) == "Not identified")
        #expect(DebugFormat.peerLabel(nil) == "Not identified")
    }

    // MARK: the Security adapter, against real sockets

    @Test func readsTheAuditTokenOfAConnectedPeer() throws {
        let srv = RawServer { fd, _ in
            _ = RawServer.readLine(fd); close(fd)
        }
        defer { srv.stop() }
        let s = try connectRaw(srv.path)
        defer { close(s) }
        // The listener is this test process.
        let token = try #require(PeerIdentifier.auditToken(socket: s))
        #expect(token.count == MemoryLayout<audit_token_t>.size)
        let me = try #require(SocketHolder.executablePath(pid: getpid()))
        #expect(PeerIdentifier.path(auditToken: token) == me)
        #expect(PeerIdentifier.satisfies(auditToken: token, requirement: "anchor apple generic or !anchor apple generic"))
        #expect(!PeerIdentifier.satisfies(auditToken: token, requirement: SocketHolder.helperRequirement))
        #expect(!PeerIdentifier.satisfies(auditToken: token, requirement: "not a requirement ("), "a bad requirement")
        #expect(PeerIdentifier.live(bundlePath: bundle).identify(socket: s) == .other)
        // No socket, or not a Unix socket: no token.
        #expect(PeerIdentifier.auditToken(socket: -1) == nil)
        var p: [Int32] = [-1, -1]
        try #require(pipe(&p) == 0)
        defer { close(p[0]); close(p[1]) }
        #expect(PeerIdentifier.auditToken(socket: p[0]) == nil)
        // A token naming no live code.
        let bogus = Data(count: MemoryLayout<audit_token_t>.size)
        #expect(PeerIdentifier.path(auditToken: bogus) == nil)
        #expect(!PeerIdentifier.satisfies(auditToken: bogus, requirement: "anchor apple generic or !anchor apple generic"))
        #expect(PeerIdentifier.path(auditToken: Data([1])) == nil, "a short token")
    }

    /// socket.lock says our helper holds the socket, but the process actually listening is an
    /// impostor (ad hoc signed with our identifier): only the token tells the truth.
    @Test func anImpostorBehindALyingLockIsNotOurs() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let helpers = dir.appendingPathComponent("App.app/Contents/Helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let helperBin = helpers.appendingPathComponent("fsearch")
        let impostorBin = dir.appendingPathComponent("fsearch")
        try compileListener(to: helperBin)
        try compileListener(to: impostorBin)
        try run("/usr/bin/codesign", ["-f", "-s", "-", "-i", SocketHolder.helperIdentifier, impostorBin.path])

        let helperSock = dir.appendingPathComponent("h.sock").path
        let impostorSock = dir.appendingPathComponent("i.sock").path
        let helper = try launch(helperBin, socket: helperSock)
        defer { helper.terminate(); helper.waitUntilExit() }
        let impostor = try launch(impostorBin, socket: impostorSock)
        defer { impostor.terminate(); impostor.waitUntilExit() }

        let real = try #require(SocketHolder.executablePath(pid: helper.processIdentifier))
        let bundlePath = String(real.dropLast("/Contents/Helpers/fsearch".count))
        try "\(helper.processIdentifier)".write(to: dir.appendingPathComponent("socket.lock"), atomically: true, encoding: .utf8)
        let lock = SocketHolder.read(dataDir: dir, bundlePath: bundlePath)
        #expect(lock == .ours, "the lock names our real helper")

        let id = PeerIdentifier.live(bundlePath: bundlePath)
        let toImpostor = try connectRaw(impostorSock)
        defer { close(toImpostor) }
        let impostorPeer = id.identify(socket: toImpostor)
        #expect(impostorPeer == .other)
        #expect(DaemonPlan.holder(peer: impostorPeer, lock: { lock }) == .other)

        let toHelper = try connectRaw(helperSock)
        defer { close(toHelper) }
        #expect(id.identify(socket: toHelper) == .ours, "our bundle's helper, named by its token")
        #expect(PeerIdentifier.live(bundlePath: bundle).identify(socket: toHelper) == .other, "another bundle's")
    }

    // MARK: the connection records its peer

    @Test func aLineSocketKnowsItsPeerWhileConnected() throws {
        let srv = RawServer { fd, _ in
            while RawServer.readLine(fd) { RawServer.send(fd, "{}\n") }
            close(fd)
        }
        defer { srv.stop() }
        let calls = Mutex(0)
        let s = LineSocket(
            path: srv.path, timeout: 2,
            identifyPeer: { fd in
                calls.withLock { $0 += 1 }
                return fd >= 0 ? .ours : nil
            })
        #expect(s.peer == nil, "not connected yet")
        _ = try s.roundTrip(Data("{}".utf8))
        #expect(s.peer == .ours)
        _ = try s.roundTrip(Data("{}".utf8))
        #expect(calls.withLock { $0 } == 1, "identified once per connection")
        s.close()
        #expect(s.peer == nil)
        let plain = LineSocket(path: srv.path, timeout: 2)
        _ = try plain.roundTrip(Data("{}".utf8))
        #expect(plain.peer == nil, "identification is opt-in")
    }

    @Test func aDaemonClientPublishesItsPeer() async throws {
        let d = FakeDaemon { _ in ["ok": true] }
        defer { d.stop() }
        let c = DaemonClient(socketPath: d.path, identifyPeer: .live(bundlePath: bundle))
        #expect(c.peer == nil)
        try await c.ping()
        #expect(c.peer == .other, "the test process isn't our helper")
        d.stop()
        await #expect(throws: DaemonError.self) { try await c.ping() }
        #expect(c.peer == nil, "a dropped connection has no peer")
        #expect(DaemonClient(socketPath: d.path).peer == nil)
    }

    // MARK: helpers

    private func connectRaw(_ path: String) throws -> Int32 {
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(s >= 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { p in
            _ = path.withCString { strncpy(p.baseAddress!.assumingMemoryBound(to: CChar.self), $0, p.count - 1) }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let r = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(s, $0, len) } }
        if r != 0 { close(s) }
        try #require(r == 0, "connect \(path): errno \(errno)")
        return s
    }

    /// A process that listens on the Unix socket named by argv[1] and then just waits.
    private func compileListener(to bin: URL) throws {
        let src = bin.deletingLastPathComponent().appendingPathComponent("listener-\(UUID().uuidString.prefix(6)).c")
        try """
        #include <string.h>
        #include <sys/socket.h>
        #include <sys/un.h>
        #include <unistd.h>
        int main(int argc, char **argv) {
            int s = socket(AF_UNIX, SOCK_STREAM, 0);
            struct sockaddr_un a; memset(&a, 0, sizeof a);
            a.sun_family = AF_UNIX;
            strncpy(a.sun_path, argv[1], sizeof a.sun_path - 1);
            unlink(argv[1]);
            if (bind(s, (struct sockaddr *)&a, sizeof a) != 0 || listen(s, 4) != 0) return 1;
            sleep(30);
            return 0;
        }
        """.write(to: src, atomically: true, encoding: .utf8)
        try run("/usr/bin/xcrun", ["clang", "-o", bin.path, src.path])
    }

    private func launch(_ bin: URL, socket path: String) throws -> Process {
        let p = Process()
        p.executableURL = bin
        p.arguments = [path]
        try p.run()
        let deadline = Date().addingTimeInterval(10)
        var st = stat()
        while lstat(path, &st) != 0 || (st.st_mode & S_IFMT) != S_IFSOCK {
            try #require(Date() < deadline && p.isRunning, "\(bin.lastPathComponent) never listened")
            usleep(10_000)
        }
        return p
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        try #require(p.terminationStatus == 0, "\(tool) \(args)")
    }

    private func tempDir() -> URL {
        // Short: the listeners' socket paths must fit sun_path.
        let d = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fsk-peer-\(UUID().uuidString.prefix(6))")
        try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
}

extension PeerIdentifier {
    /// Every check fails; tests replace the parts they exercise.
    static func stub(bundlePath: String) -> PeerIdentifier {
        PeerIdentifier(
            auditToken: { _ in nil }, path: { _ in nil }, satisfies: { _, _ in false }, appTeamSigned: { true }, bundlePath: bundlePath)
    }
}
