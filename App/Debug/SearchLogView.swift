import AppKit
import FSearchKit
import SwiftUI
import UniformTypeIdentifiers
import os

/// Debug window: the search log, newest first, with a filter, export and clear.
struct SearchLogView: View {
    @EnvironmentObject var app: AppState
    @State private var rows: [SearchLog.Record] = []
    /// Bumped whenever `rows` is replaced, so the filter re-runs.
    @State private var rowsGen = 0
    @State private var shown: [SearchLog.Record] = []
    @State private var filter = ""
    @State private var exportError: String?

    private struct FilterKey: Equatable { let filter: String; let gen: Int }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Filter", text: $filter)
                Button("Export…", action: export)
                Button("Clear Log") {
                    app.log.clear(); setRows([])
                }
            }.padding([.horizontal, .top])
            if let exportError {
                Text(exportError).font(.caption).foregroundStyle(.red)
                    .textSelection(.enabled).padding(.horizontal)
            }
            Table(shown) {
                TableColumn("Time") { Text($0.time.formatted(date: .omitted, time: .standard)) }
                TableColumn("Mode", value: \.mode)
                TableColumn("Query", value: \.query)
                TableColumn("Results") { Text("\($0.results)") }
                TableColumn("Daemon") { Text(DebugFormat.daemonMs($0.tookUs)) }
                TableColumn("Round trip") { Text(DebugFormat.roundTrip($0.roundTripMs)) }
                TableColumn("Error") { Text($0.error ?? "") }
            }
        }
        .frame(minWidth: 760, minHeight: 420)
        // Polls only while this window's view is on screen. Re-reads the log
        // only when its size or modification date changed, off the main actor.
        .task {
            let log = app.log
            var last: DebugFormat.FileStamp?
            var loaded = false
            while !Task.isCancelled {
                let stamp = await Task.detached { DebugFormat.FileStamp(of: log.file) }.value
                if !loaded || stamp != last {
                    let r = await Task.detached { log.entries() }.value
                    if Task.isCancelled { break }
                    last = stamp
                    loaded = true
                    setRows(r)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        // Filtering runs on a copy off the main actor; typing is debounced.
        .task(id: FilterKey(filter: filter, gen: rowsGen)) {
            if !filter.isEmpty {
                try? await Task.sleep(for: .milliseconds(150))
                if Task.isCancelled { return }
            }
            let r = rows, f = filter
            let s = await Task.detached { DebugFormat.shown(r, filter: f) }.value
            if !Task.isCancelled { shown = s }
        }
    }

    private func setRows(_ r: [SearchLog.Record]) {
        rows = r
        rowsGen &+= 1
    }

    private func export() {
        let p = NSSavePanel()
        p.nameFieldStringValue = "fsearch-searches.jsonl"
        p.allowedContentTypes = [UTType(filenameExtension: "jsonl") ?? .plainText]
        guard p.runModal() == .OK, let url = p.url else { return }
        do {
            try DebugFormat.jsonl(rows).write(to: url, options: .atomic)
            exportError = nil
        } catch {
            Log.debug.error("search log export failed: \(error.localizedDescription, privacy: .private)")
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }
}

extension SearchLog.Record: @retroactive Identifiable {
    public var id: String { "\(time.timeIntervalSince1970)-\(mode)-\(query)-\(roundTripMs)" }
}
