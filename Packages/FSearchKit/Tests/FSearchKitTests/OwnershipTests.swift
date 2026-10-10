import Darwin
import Foundation
import Testing

@testable import FSearchKit

@Suite struct SocketHolderTests {
    @Test func pidIsTheDaemonsDecimalText() {
        #expect(SocketHolder.pid(fromLock: "123") == 123)
        #expect(SocketHolder.pid(fromLock: " 4567\n") == 4567)
        for bad in ["", "abc", "1", "0", "-5", "12x"] { #expect(SocketHolder.pid(fromLock: bad) == nil, "\(bad)") }
    }

    @Test func classifiesByTheHoldersPath() {
        let bundle = "/Applications/FSearch.app"
        #expect(SocketHolder.classify(pid: nil, path: nil, bundlePath: bundle) == SocketHolder.none)
        #expect(SocketHolder.classify(pid: 99, path: nil, bundlePath: bundle) == SocketHolder.none, "a dead pid")
        #expect(SocketHolder.classify(pid: 99, path: bundle + "/Contents/Helpers/fsearch", bundlePath: bundle) == .ours)
        #expect(SocketHolder.classify(pid: 99, path: "/opt/homebrew/bin/fsearch", bundlePath: bundle) == .other)
        #expect(SocketHolder.classify(pid: 99, path: "/Applications/FSearch.app2/fsearch", bundlePath: bundle) == .other)
        #expect(SocketHolder.classify(pid: 99, path: bundle + "/Contents/Helpers/fsearch", bundlePath: bundle + "/") == .ours)
    }

    private func tempDir() -> URL {
        let d = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fsk-lock-\(UUID().uuidString.prefix(8))")
        try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func readsTheLiveHolder() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(SocketHolder.read(dataDir: dir, bundlePath: "/") == SocketHolder.none, "no socket.lock")
        try "\(getpid())".write(to: dir.appendingPathComponent("socket.lock"), atomically: true, encoding: .utf8)
        let me = try #require(SocketHolder.executablePath(pid: getpid()))
        let myDir = (me as NSString).deletingLastPathComponent
        #expect(SocketHolder.read(dataDir: dir, bundlePath: myDir) == .ours)
        #expect(SocketHolder.read(dataDir: dir, bundlePath: "/nonexistent/FSearch.app") == .other)
    }

    @Test func aDeadPidIsNoHolder() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try p.run()
        p.waitUntilExit()
        try "\(p.processIdentifier)".write(to: dir.appendingPathComponent("socket.lock"), atomically: true, encoding: .utf8)
        #expect(SocketHolder.executablePath(pid: p.processIdentifier) == nil)
        #expect(SocketHolder.read(dataDir: dir, bundlePath: "/") == SocketHolder.none)
    }

    @Test func ownershipNeedsOurHelperEnabledAndNoOtherHolder() {
        #expect(DaemonPlan.owns(helperEnabled: true, holder: .ours))
        // Our helper is enabled and nothing holds the socket (it's restarting): still ours.
        #expect(DaemonPlan.owns(helperEnabled: true, holder: .none))
        // A CLI daemon holds the socket: our helper yielded to it, so it isn't ours.
        #expect(!DaemonPlan.owns(helperEnabled: true, holder: .other))
        for h in [SocketHolder.ours, .none, .other] { #expect(!DaemonPlan.owns(helperEnabled: false, holder: h)) }
    }
}

@Suite struct HelperUpdateTests {
    @Test func aChangedHelperOfOursIsRestartedOnce() {
        #expect(DaemonPlan.helperUpdate(owns: true, justRegistered: false, stored: "1:10:5", current: "2:11:6") == .restartThenStore)
        // Upgrading from a build that stored nothing: the running helper may be old.
        #expect(DaemonPlan.helperUpdate(owns: true, justRegistered: false, stored: nil, current: "2:11:6") == .restartThenStore)
    }

    @Test func aFreshOrUnchangedHelperIsLeftRunning() {
        #expect(DaemonPlan.helperUpdate(owns: true, justRegistered: true, stored: nil, current: "2") == .store)
        #expect(DaemonPlan.helperUpdate(owns: true, justRegistered: true, stored: "1", current: "2") == .store)
        #expect(DaemonPlan.helperUpdate(owns: true, justRegistered: false, stored: "2", current: "2") == .nothing)
        #expect(DaemonPlan.helperUpdate(owns: true, justRegistered: false, stored: "2", current: nil) == .nothing)
    }

    @Test func aDaemonWeDontOwnIsNeverRestarted() {
        for stored in [nil, "1", "2"] {
            for fresh in [false, true] {
                #expect(DaemonPlan.helperUpdate(owns: false, justRegistered: fresh, stored: stored, current: "2") == .nothing)
            }
        }
    }
}

@Suite struct LaunchCheckTests {
    @Test func translocationAndReadOnlyVolumesAreProblems() {
        #expect(InstallLocation.problem(bundlePath: "/Applications/FSearch.app", translocated: false, readOnlyVolume: false) == nil)
        #expect(
            InstallLocation.problem(bundlePath: "/Applications/FSearch.app", translocated: true, readOnlyVolume: false) == .translocated)
        #expect(
            InstallLocation.problem(
                bundlePath: "/private/var/folders/x/T/AppTranslocation/ABC/d/FSearch.app", translocated: false, readOnlyVolume: true)
                == .translocated)
        #expect(
            InstallLocation.problem(bundlePath: "/Volumes/FSearch/FSearch.app", translocated: false, readOnlyVolume: true)
                == .readOnlyVolume)
        for p in [InstallLocation.Problem.translocated, .readOnlyVolume] {
            #expect(p.message.contains("Applications"))
        }
    }

    @Test func anotherCopyOfTheAppIsFound() {
        #expect(SingleInstance.other(pids: [10, 20], me: 10) == 20)
        #expect(SingleInstance.other(pids: [10], me: 10) == nil)
        #expect(SingleInstance.other(pids: [], me: 10) == nil)
    }
}
