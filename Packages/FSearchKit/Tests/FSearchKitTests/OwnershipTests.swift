import Darwin
import Foundation
import Security
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

    @Test func anUpdatedAppsOldHelperIsStillOurs() {
        let bundle = "/Applications/FSearch.app"
        // Sparkle or Finder swapped the bundle: the running helper now lives in the Trash or a temp dir.
        for moved in [
            "/Users/me/.Trash/FSearch.app/Contents/Helpers/fsearch",
            "/private/var/folders/x/T/org.sparkle-project/FSearch.app/Contents/Helpers/fsearch",
        ] {
            #expect(SocketHolder.classify(pid: 99, path: moved, signedAsHelper: false, bundlePath: bundle) == .ours, "\(moved)")
        }
        // Signed as our helper by our team, wherever it runs from (or with no path left to read).
        #expect(SocketHolder.classify(pid: 99, path: "/private/tmp/x/fsearch", signedAsHelper: true, bundlePath: bundle) == .ours)
        #expect(SocketHolder.classify(pid: 99, path: nil, signedAsHelper: true, bundlePath: bundle) == .ours)
        #expect(SocketHolder.classify(pid: nil, path: nil, signedAsHelper: true, bundlePath: bundle) == SocketHolder.none)
    }

    @Test func anythingElseIsNeverOurs() {
        let bundle = "/Applications/FSearch.app"
        for path in [
            "/opt/homebrew/bin/fsearch", "/Applications/Other.app/Contents/Helpers/fsearch",
            "/Applications/XFSearch.app/Contents/Helpers/fsearch", "/Applications/FSearch.app/Contents/Helpers/fsearch2",
            "/Applications/FSearch.app/Contents/MacOS/fsearch", "/x/FSearch.app/Contents/Helpers/fsearch/../../../evil",
        ] {
            #expect(
                SocketHolder.classify(pid: 99, path: path, signedAsHelper: false, bundlePath: "/Applications/Mine.app") == .other,
                "\(path)")
        }
        #expect(SocketHolder.classify(pid: 99, path: "/opt/homebrew/bin/fsearch", signedAsHelper: false, bundlePath: bundle) == .other)
    }

    @Test func theHelperRequirementNamesOurTeamNotJustTheIdentifier() {
        let r = SocketHolder.helperRequirement
        #expect(r.contains("identifier \"\(SocketHolder.helperIdentifier)\""))
        #expect(r.contains("anchor apple generic"))
        #expect(r.contains("certificate leaf[subject.OU] = \"MR3WJZ83MR\""))
        var req: SecRequirement?
        #expect(SecRequirementCreateWithString(r as CFString, [], &req) == errSecSuccess, "it parses")
    }

    @Test func readsThroughInjectedResolvers() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "4242".write(to: dir.appendingPathComponent("socket.lock"), atomically: true, encoding: .utf8)
        let bundle = "/Applications/FSearch.app"
        let ours = SocketHolder.read(
            dataDir: dir, bundlePath: bundle, path: { $0 == 4242 ? "/tmp/gone/fsearch" : nil },
            signedAsHelper: { $0 == 4242 })
        #expect(ours == .ours)
        let other = SocketHolder.read(
            dataDir: dir, bundlePath: bundle, path: { _ in "/opt/homebrew/bin/fsearch" }, signedAsHelper: { _ in false })
        #expect(other == .other)
        let gone = SocketHolder.read(dataDir: dir, bundlePath: bundle, path: { _ in nil }, signedAsHelper: { _ in false })
        #expect(gone == SocketHolder.none)
    }

    @Test func checksARunningProcessAgainstARequirement() throws {
        // The linker signs every arm64 binary, ad hoc at least: the test runner is signed, but not by our team.
        #expect(!SocketHolder.isSignedAsHelper(pid: getpid()))
        #expect(SocketHolder.isSignedAsHelper(pid: getpid(), requirement: "anchor apple generic or !anchor apple generic"))
        #expect(!SocketHolder.isSignedAsHelper(pid: getpid(), requirement: "not a requirement ("), "a bad requirement")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try p.run()
        p.waitUntilExit()
        #expect(!SocketHolder.isSignedAsHelper(pid: p.processIdentifier, requirement: "anchor apple"), "a dead pid")
    }

    @Test func anAdHocSignatureClaimingOurIdentifierIsNotOurs() throws {
        // Anyone can sign ad hoc with any identifier; only our team's certificate makes it our helper.
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let src = dir.appendingPathComponent("main.c")
        let bin = dir.appendingPathComponent("fsearch")
        try "#include <unistd.h>\nint main(void) { sleep(30); return 0; }\n".write(to: src, atomically: true, encoding: .utf8)
        try run("/usr/bin/xcrun", ["clang", "-o", bin.path, src.path])
        try run("/usr/bin/codesign", ["-f", "-s", "-", "-i", SocketHolder.helperIdentifier, bin.path])
        let p = Process()
        p.executableURL = bin
        try p.run()
        defer { p.terminate(); p.waitUntilExit() }
        let identifierOnly = "identifier \"\(SocketHolder.helperIdentifier)\""
        #expect(SocketHolder.isSignedAsHelper(pid: p.processIdentifier, requirement: identifierOnly), "it does claim the identifier")
        #expect(!SocketHolder.isSignedAsHelper(pid: p.processIdentifier))
        let lock = dir.appendingPathComponent("socket.lock")
        try "\(p.processIdentifier)".write(to: lock, atomically: true, encoding: .utf8)
        #expect(SocketHolder.read(dataDir: dir, bundlePath: "/Applications/FSearch.app") == .other)
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

@Suite struct DataOwnershipTests {
    /// The shared data folder is the app's to trash only when our helper is enabled and positively holds the socket.
    @Test func onlyOurHoldingHelperOwnsTheData() {
        #expect(DaemonPlan.dataOwnership(helperEnabled: true, holder: .ours) == .ours)
        #expect(DaemonPlan.dataOwnership(helperEnabled: true, holder: .other) == .otherDaemon)
        // No pid in socket.lock (an older daemon, or nothing running): not proof that the index is ours.
        #expect(DaemonPlan.dataOwnership(helperEnabled: true, holder: .none) == .unconfirmed)
        for h in [SocketHolder.ours, .none, .other] {
            #expect(DaemonPlan.dataOwnership(helperEnabled: false, holder: h) == .helperOff)
        }
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
