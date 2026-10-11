import Foundation
import Testing

@testable import FSearch

extension AppTests {
    /// Moving the app into Applications, run against a temp folder and a fake
    /// workspace: nothing is copied into the real /Applications and nothing is launched.
    @Suite @MainActor
    struct InstallMoverTests {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fsa-move-\(UUID().uuidString.prefix(8))")
        var apps: URL { root.appendingPathComponent("Applications") }
        var source: URL { root.appendingPathComponent("Downloads/FSearch.app") }
        var inner: URL { source.appendingPathComponent("Contents/Info.plist") }

        /// A downloaded app: a bundle folder and a file inside, both quarantined.
        func makeDownload() throws {
            let fm = FileManager.default
            try fm.createDirectory(at: inner.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "plist".write(to: inner, atomically: true, encoding: .utf8)
            for u in [source, inner] { try #require(quarantine(u, set: true)) }
        }

        @discardableResult
        func quarantine(_ u: URL, set: Bool = false) -> Bool {
            let name = "com.apple.quarantine"
            if set {
                let v = "0081;00000000;Safari;"
                return setxattr(u.path, name, v, v.utf8.count, 0, XATTR_NOFOLLOW) == 0
            }
            return getxattr(u.path, name, nil, 0, 0, XATTR_NOFOLLOW) >= 0
        }

        func cleanUp() { try? FileManager.default.removeItem(at: root) }

        @Test func copiesClearsQuarantineAndRelaunchesFromTheCopy() throws {
            defer { cleanUp() }
            try makeDownload()
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            let ws = FakeWorkspace()
            var launched: [Process] = []
            InstallMover.moveToApplications(from: source, applications: apps, workspace: ws) { launched.append($0) }

            let dest = apps.appendingPathComponent("FSearch.app")
            #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("Contents/Info.plist").path))
            #expect(FileManager.default.fileExists(atPath: source.path), "a copy, not a move")
            // Otherwise macOS translocates the copy again on its first launch.
            #expect(!quarantine(dest))
            #expect(!quarantine(dest.appendingPathComponent("Contents/Info.plist")))
            #expect(quarantine(source), "the download keeps its own")
            #expect(launched.count == 1)
            #expect(launched.first?.executableURL?.path == "/bin/sh")
            #expect(launched.first?.arguments == InstallMover.relaunchArguments(app: dest, waitingFor: getpid()))
            #expect(ws.revealed.isEmpty)
        }

        /// An older copy in Applications is never overwritten: both are shown in Finder.
        @Test func anExistingCopyIsRevealedNotReplaced() throws {
            defer { cleanUp() }
            try makeDownload()
            let dest = apps.appendingPathComponent("FSearch.app")
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let ws = FakeWorkspace()
            var launches = 0
            InstallMover.moveToApplications(from: source, applications: apps, workspace: ws) { _ in launches += 1 }
            #expect(ws.revealed.map { $0.map(\.path) } == [[source.path, dest.path]])
            #expect(launches == 0)
            #expect(!FileManager.default.fileExists(atPath: dest.appendingPathComponent("Contents").path))
        }

        /// A failed copy shows the app and the Applications folder instead, and launches nothing.
        @Test func aFailedCopyRevealsTheAppAndApplications() throws {
            defer { cleanUp() }
            try makeDownload()
            let ws = FakeWorkspace()
            var launches = 0
            // The Applications folder doesn't exist, so the copy fails.
            InstallMover.moveToApplications(from: source, applications: apps, workspace: ws) { _ in launches += 1 }
            #expect(ws.revealed.map { $0.map(\.path) } == [[source.path, apps.path]])
            #expect(launches == 0)
        }

        /// The relaunch failing to start falls back to Finder too.
        @Test func aFailedRelaunchRevealsTheAppAndApplications() throws {
            defer { cleanUp() }
            try makeDownload()
            try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
            let ws = FakeWorkspace()
            InstallMover.moveToApplications(from: source, applications: apps, workspace: ws) { _ in throw TestError("no sh") }
            #expect(ws.revealed.map { $0.map(\.path) } == [[source.path, apps.path]])
        }

        /// A bundle that isn't translocated is its own original.
        @Test func anUntranslocatedBundleIsItsOwnOriginal() throws {
            defer { cleanUp() }
            try makeDownload()
            #expect(!InstallMover.isTranslocated(source))
            #expect(InstallMover.originalURL(of: source) == source)
        }
    }
}
