import AppKit
import FSearchKit
import SwiftUI

struct IndexDetailsView: View {
    @EnvironmentObject var app: AppState
    @State private var skipped: [String] = []
    @State private var logTail = ""
    private let dataDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/FSearch")

    var body: some View {
        Form {
            if case let .running(s) = app.daemon.state {
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
            } else {
                Text(String(describing: app.daemon.state)).foregroundStyle(.secondary)
            }
            Section("Folders the index lacks (skipped)") {
                if skipped.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(skipped, id: \.self) { Text($0).font(.system(.caption, design: .monospaced)) }
                }
            }
            Section("daemon.log (last 30 lines)") {
                ScrollView {
                    Text(logTail).font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }.frame(height: 160)
            }
            HStack {
                Button("Reveal Data Folder") { NSWorkspace.shared.activateFileViewerSelecting([dataDir]) }
                Button("Save Now") { Task { await app.daemon.saveNow() } }
                Button("Restart Daemon") { Task { await app.daemon.restart() } }
                Button("Copy All") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report(), forType: .string)
                }
            }
        }
        .formStyle(.grouped).frame(minWidth: 520, minHeight: 600)
        // Runs only while this window's view is on screen; cancelled when it goes away.
        .task {
            while !Task.isCancelled {
                await app.daemon.refresh()
                load()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View { LabeledContent(k, value: v) }

    private func load() {
        skipped = DebugFormat.lines((try? String(contentsOf: dataDir.appendingPathComponent("skipped"), encoding: .utf8)) ?? "")
        logTail = DebugFormat.tail(of: dataDir.appendingPathComponent("daemon.log"), lines: 30)
    }

    private func report() -> String {
        "state: \(app.daemon.state)\nskipped:\n\(skipped.joined(separator: "\n"))\nlog:\n\(logTail)"
    }
}
