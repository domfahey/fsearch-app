import Darwin
import Foundation
import Testing

@testable import FSearchKit

/// The fixture daemon must not outlive its test process. Serialized: both
/// tests start real daemons and the sweep must not race a sibling's setup.
@Suite(.serialized, .enabled(if: RealDaemon.binary != nil, "run scripts/build-daemon.sh first"))
struct RealDaemonLifetimeTests {
    private func daemonPID(under home: String) -> Int32? {
        let out = RealDaemon.sh("/bin/ps", ["-axww", "-o", "pid=,command="])
        for line in out.split(separator: "\n") where line.hasSuffix("Vendor/fsearch serve") {
            let pid = Int32(line.split(separator: " ")[0])!
            if RealDaemon.sh("/bin/ps", ["eww", "-o", "command=", "-p", String(pid)]).contains("HOME=\(home) ") { return pid }
        }
        return nil
    }

    private func waitFor(_ secs: Double, _ cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(secs)
        while Date() < end { if cond() { return true }; Thread.sleep(forTimeInterval: 0.1) }
        return cond()
    }

    /// Writer of the pipe (a `sleep`) is SIGKILLed: the wrapper must stop the
    /// daemon and delete the temp dir within ~6 s.
    @Test func wrapperStopsDaemonWhenPipeWriterIsKilled() throws {
        let bin = RealDaemon.binary!.path
        let home = "/private/tmp/fsk-wd\(UUID().uuidString.prefix(4))"
        try FileManager.default.createDirectory(atPath: home + "/root", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        let writer = Process()
        writer.executableURL = URL(fileURLWithPath: "/bin/sleep")
        writer.arguments = ["300"]
        let pipe = Pipe()
        writer.standardOutput = pipe
        let wrapper = Process()
        wrapper.executableURL = URL(fileURLWithPath: "/bin/sh")
        wrapper.arguments = ["-c", RealDaemon.wrapperScript, bin, home]
        wrapper.standardInput = pipe.fileHandleForReading
        wrapper.environment = ["HOME": home, "FSEARCH_ROOT": home + "/root"]
        try writer.run()
        try wrapper.run()
        // Our copies of the pipe must not keep it open.
        try pipe.fileHandleForWriting.close()
        try pipe.fileHandleForReading.close()
        #expect(waitFor(10) { daemonPID(under: home) != nil })
        let pid = try #require(daemonPID(under: home))
        kill(writer.processIdentifier, SIGKILL)
        #expect(waitFor(6) { kill(pid, 0) != 0 })
        #expect(waitFor(2) { !FileManager.default.fileExists(atPath: home) })
        #expect(!wrapper.isRunning || waitFor(2) { !wrapper.isRunning })
    }

    /// An orphan (ppid 1) fixture daemon is swept; a daemon with another HOME is not.
    @Test func sweepKillsOrphanFixtureDaemonsOnly() throws {
        let bin = RealDaemon.binary!.path
        let fsk = "/private/tmp/fsk-sw\(UUID().uuidString.prefix(4))"
        let other = "/private/tmp/notfsk-sw\(UUID().uuidString.prefix(4))"
        for h in [fsk, other] { try FileManager.default.createDirectory(atPath: h + "/root", withIntermediateDirectories: true) }
        defer { for h in [fsk, other] { try? FileManager.default.removeItem(atPath: h) } }
        // The subshell exits at once, orphaning the daemons to launchd.
        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = [
            "-c",
            """
            (HOME=\(fsk) FSEARCH_ROOT=\(fsk)/root "\(bin)" serve </dev/null >/dev/null 2>&1 &)
            (HOME=\(other) FSEARCH_ROOT=\(other)/root "\(bin)" serve </dev/null >/dev/null 2>&1 &)
            """,
        ]
        try sh.run()
        sh.waitUntilExit()
        #expect(waitFor(10) { daemonPID(under: fsk) != nil && daemonPID(under: other) != nil })
        let keep = try #require(daemonPID(under: other))
        defer { kill(keep, SIGKILL) }
        RealDaemon.sweep()
        #expect(daemonPID(under: fsk) == nil)
        #expect(!FileManager.default.fileExists(atPath: fsk))
        #expect(kill(keep, 0) == 0)
    }

    /// Manual harness (FSK_HOLD=1): start a RealDaemon and wait to be SIGKILLed.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FSK_HOLD"] != nil))
    func holdForKill() throws {
        let d = try RealDaemon(files: ["a.txt": "x"])
        try d.home.path.write(toFile: ProcessInfo.processInfo.environment["FSK_HOLD"]!, atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 120)
        withExtendedLifetime(d) {}
    }
}
