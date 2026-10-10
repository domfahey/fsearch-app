import AppKit
import FSearchKit
import Foundation

/// The workspace in test mode (UI tests and the unit-test host): it records
/// every action and performs none, so a test that presses ↵ or ⌘↵, or picks
/// Open With, Terminal or Trash, never opens, reveals or trashes a real file.
/// Each action is one line in `log` ("open <path>"), which a UI test reads
/// from the test daemon's temp folder. App lookups are real (read-only).
@MainActor
final class TestModeWorkspace: Workspace {
    let log: URL
    private(set) var actions: [String] = []

    init(log: URL) { self.log = log }

    /// Next to the test daemon's socket, inside its temp HOME.
    static func logFile(socketPath: String) -> URL {
        DebugFormat.dataDir(socketPath: socketPath).appendingPathComponent("actions.log")
    }

    private func record(_ line: String) {
        actions.append(line)
        let data = Data((line + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: log) {
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: data)
        } else {
            try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: log)
        }
    }

    func open(_ url: URL) { record("open \(url.isFileURL ? url.path : url.absoluteString)") }

    func open(_ urls: [URL], withApplicationAt app: URL, completion: (@Sendable (Error?) -> Void)?) {
        record("openWith \(app.lastPathComponent) \(urls.map(\.path).joined(separator: " "))")
        completion?(nil)
    }

    func activateFileViewerSelecting(_ urls: [URL]) { record("reveal \(urls.map(\.path).joined(separator: " "))") }
    func urlForApplication(withBundleIdentifier id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }
    func urlsForApplications(toOpen url: URL) -> [URL] { NSWorkspace.shared.urlsForApplications(toOpen: url) }

    /// Real and read-only: a UI test's results are real files in its fixture.
    func fileInfo(atPath path: String) -> FileInfo? { FileInfo.onDisk(path) }

    func trash(_ url: URL) throws { record("trash \(url.path)") }
}
