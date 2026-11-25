import AppKit
import FSearchKit
import SwiftUI
import os

/// Debug window: the daemon's index statistics, skipped folders and log tail, with Save Now and Restart Daemon.
struct IndexDetailsView: View {
    @EnvironmentObject var app: AppState
    @State private var skipped: [String] = []
    @State private var logTail = ""
    @State private var skippedStamp: DebugFormat.FileStamp?
    @State private var logStamp: DebugFormat.FileStamp?
    /// The running daemon's folder (a temp folder in test mode).
    private var dataDir: URL { DebugFormat.dataDir(socketPath: app.options.socketPath) }

    var body: some View {
        Form {
            // Observes DaemonManager directly: AppState doesn't forward its changes.
            IndexStatsSections(daemon: app.daemon)
            Section("Folders the index lacks (skipped)") {
                if skipped.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(skipped, id: \.self) { Text($0).font(.system(.caption, design: .monospaced)) }
                }
            }
            Section("daemon.log (last 30 lines)") {
                ScrollView {
                    Text(Self.logText(logTail)).font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }.frame(height: 160)
            }
            HStack {
                Button("Reveal Data Folder") { FileActions.workspace.activateFileViewerSelecting([dataDir]) }
                Button("Save Now") {
                    Log.debug.info("Save Now pressed"); Task { await app.daemon.saveNow() }
                }
                Button("Restart Daemon") {
                    Log.debug.info("Restart Daemon pressed"); Task { await app.daemon.restart() }
                }
                Button("Copy All") {
                    FileActions.pasteboard.clearContents()
                    FileActions.pasteboard.setString(report(), forType: .string)
                }
            }
        }
        .formStyle(.grouped).frame(minWidth: 520, minHeight: 600)
        // Runs only while this window's view is on screen; cancelled when it goes away.
        .task {
            while !Task.isCancelled {
                await load()
                await app.daemon.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Reads the skipped list and the log tail off the main actor, skipping unchanged files.
    private func load() async {
        let dir = dataDir
        let prevSkipped = skippedStamp, prevLog = logStamp
        let result = await Task.detached {
            let skippedURL = dir.appendingPathComponent("skipped")
            let logURL = dir.appendingPathComponent("daemon.log")
            let nextSkipped = DebugFormat.FileStamp(of: skippedURL)
            let nextLog = DebugFormat.FileStamp(of: logURL)
            let newSkipped: [String]? =
                nextSkipped == prevSkipped
                ? nil : DebugFormat.lines((try? String(contentsOf: skippedURL, encoding: .utf8)) ?? "")
            let newLog: String? = nextLog == prevLog ? nil : DebugFormat.tail(of: logURL, lines: 30)
            return (nextSkipped, newSkipped, nextLog, newLog)
        }.value
        skippedStamp = result.0
        if let s = result.1 { skipped = s }
        logStamp = result.2
        if let t = result.3 { logTail = t }
    }

    /// Shown instead of an empty log: the bundled helper can't write one.
    static let noLogNote =
        "No daemon.log. FSearch's own background helper doesn't write one: its launchd plist is fixed inside the app and can't name a log file in your home folder. A daemon started by the fsearch command-line tool writes its log here."

    static func logText(_ tail: String) -> String { tail.isEmpty ? noLogNote : tail }

    private func report() -> String {
        "state: \(app.daemon.state)\nskipped:\n\(skipped.joined(separator: "\n"))\nlog:\n\(logTail)"
    }
}

/// The daemon's stats; redraws on every DaemonManager change.
private struct IndexStatsSections: View {
    @ObservedObject var daemon: DaemonManager

    var body: some View {
        switch daemon.state {
        case let .running(s):
            Section("Index") {
                row("Entries", s.entries.formatted())
                row("Folders", s.dirs.formatted())
                row("Pending changes", "\(s.overlay.formatted()) added, \(s.removed.formatted()) removed")
                row("Last FSEvents id", "\(s.eventId)")
                row("Index size", DebugFormat.bytes(s.indexBytes))
                row("Full Disk Access", s.fullDiskAccess ? "On" : "Off")
                row("Role", s.owner ? "Owner (writes the index)" : "Follower")
            }
            Section("Content index") {
                row("Files", s.contentDocs.formatted())
                row("Segments", "\(s.contentSegments)")
                row("Size", DebugFormat.bytes(s.contentBytes))
                row("Waiting to be indexed", s.contentPending.formatted())
            }
        case let .failed(msg):
            Section("Daemon") {
                Label("Not reachable: \(msg)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).textSelection(.enabled)
            }
        case .checking:
            Section("Daemon") { Text("Checking…").foregroundStyle(.secondary) }
        case .indexing:
            Section("Daemon") { Text("Indexing…").foregroundStyle(.secondary) }
        case .needsApproval:
            Section("Daemon") {
                Text("Waiting for approval in Login Items.").foregroundStyle(.secondary)
                Button("Open Login Items Settings") { daemon.openLoginItems() }
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View { LabeledContent(k, value: v) }
}
