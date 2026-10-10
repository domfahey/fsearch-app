import AppKit
import FSearchKit
import SwiftUI
import UniformTypeIdentifiers

struct SearchLogView: View {
    @EnvironmentObject var app: AppState
    @State private var rows: [SearchLog.Record] = []
    @State private var filter = ""

    private var shown: [SearchLog.Record] { DebugFormat.shown(rows, filter: filter) }

    var body: some View {
        VStack {
            HStack {
                TextField("Filter", text: $filter)
                Button("Export…", action: export)
                Button("Clear Log") { app.log.clear(); rows = [] }
            }.padding([.horizontal, .top])
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
        // Polls only while this window's view is on screen.
        .task {
            while !Task.isCancelled {
                rows = app.log.entries()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func export() {
        let p = NSSavePanel()
        p.nameFieldStringValue = "fsearch-searches.jsonl"
        p.allowedContentTypes = [.json]
        if p.runModal() == .OK, let url = p.url { try? DebugFormat.jsonl(rows).write(to: url, options: .atomic) }
    }
}

extension SearchLog.Record: @retroactive Identifiable {
    public var id: String { "\(time.timeIntervalSince1970)-\(mode)-\(query)-\(roundTripMs)" }
}
