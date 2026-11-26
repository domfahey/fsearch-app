import Darwin
import Foundation
import Testing

@testable import FSearchKit

@Suite struct DataFolderCheckTests {
    private func temp() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("dfc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        return d
    }

    @Test func cleanFolderHasNoIssues() throws {
        let d = try temp()
        defer { try? FileManager.default.removeItem(at: d) }
        #expect(DataFolderCheck.issues(in: d).isEmpty)
    }

    @Test func missingFolderIsNotAnIssue() {
        #expect(DataFolderCheck.issues(in: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")).isEmpty)
    }

    @Test func symlinkedFolderIsFlagged() throws {
        let d = try temp()
        defer { try? FileManager.default.removeItem(at: d) }
        let target = d.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let link = d.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(DataFolderCheck.issues(in: link) == [.folderIsSymlink])
    }

    @Test func plainFileIsNotADirectory() throws {
        let d = try temp()
        defer { try? FileManager.default.removeItem(at: d) }
        let f = d.appendingPathComponent("file")
        FileManager.default.createFile(atPath: f.path, contents: Data())
        #expect(DataFolderCheck.issues(in: f).contains(.folderNotDirectory))
    }

    @Test func foreignOwnerIsFlagged() throws {
        let d = try temp()
        defer { try? FileManager.default.removeItem(at: d) }
        #expect(DataFolderCheck.issues(in: d, uid: getuid() &+ 1).contains(.folderNotOwned))
    }

    @Test func groupOrWorldWritableIsFlagged() throws {
        let d = try temp()
        defer { try? FileManager.default.removeItem(at: d) }
        chmod(d.path, 0o775)
        #expect(DataFolderCheck.issues(in: d) == [.folderWritableByOthers])
        chmod(d.path, 0o757)
        #expect(DataFolderCheck.issues(in: d) == [.folderWritableByOthers])
        chmod(d.path, 0o755)
        #expect(DataFolderCheck.issues(in: d).isEmpty)
    }

    @Test func symlinkedOrForeignSocketFilesAreFlagged() throws {
        let d = try temp()
        defer { try? FileManager.default.removeItem(at: d) }
        let elsewhere = d.appendingPathComponent("elsewhere")
        FileManager.default.createFile(atPath: elsewhere.path, contents: Data())
        try FileManager.default.createSymbolicLink(at: d.appendingPathComponent("socket.lock"), withDestinationURL: elsewhere)
        #expect(DataFolderCheck.issues(in: d) == [.fileIsSymlink("socket.lock")])
        try FileManager.default.removeItem(at: d.appendingPathComponent("socket.lock"))
        FileManager.default.createFile(atPath: d.appendingPathComponent("fsearch.sock").path, contents: Data())
        #expect(DataFolderCheck.issues(in: d, uid: getuid() &+ 1).contains(.fileNotOwned("fsearch.sock")))
    }

    @Test func unsafeToTrashCoversSymlinkAndOwnerOnly() {
        #expect(DataFolderCheck.Issue.folderIsSymlink.unsafeToTrash)
        #expect(DataFolderCheck.Issue.folderNotOwned.unsafeToTrash)
        #expect(!DataFolderCheck.Issue.folderWritableByOthers.unsafeToTrash)
        #expect(!DataFolderCheck.Issue.fileIsSymlink("socket.lock").unsafeToTrash)
    }

    @Test func everyIssueHasAMessage() {
        let all: [DataFolderCheck.Issue] = [
            .folderIsSymlink, .folderNotDirectory, .folderNotOwned, .folderWritableByOthers,
            .fileIsSymlink("socket.lock"), .fileNotOwned("fsearch.sock"),
        ]
        for i in all { #expect(!i.message.isEmpty) }
        #expect(all.last!.message.contains("fsearch.sock"))
    }
}
