import FSearchKit
import SwiftUI

/// Under the search field: a bad query's one-line error, and the quiet recovery
/// work for a daemon that restarted or is still indexing. Results resume by themselves.
struct DaemonMessageLine: View {
    @Bindable var model: SearchModel
    @ObservedObject var daemon: DaemonManager
    @State private var restarts = 0

    private var isIndexing: Bool {
        if daemon.state == .indexing { return true }
        switch model.phase {
        case .indexing, .failed(.indexing): return true
        default: return false
        }
    }

    var body: some View {
        Group {
            if case let .failed(.daemon(msg)) = model.phase {
                Text(msg).font(.caption).foregroundStyle(.red).lineLimit(2)
                    .padding(.horizontal, 16).padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("queryError")
            }
        }
        .onChange(of: model.phase) { _, p in
            switch p {
            case .results: restarts = 0
            case .failed(.disconnected) where restarts < 3:
                restarts += 1
                Task { await daemon.start(); await model.refresh() }
            default: break
            }
        }
        .task(id: isIndexing) {
            // Poll every ~2 s (up to ~5 min) until the daemon answers or gives up.
            var tries = 0
            while isIndexing && tries < 150 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { break }
                await daemon.refresh()
                await model.refresh()
                tries += 1
            }
        }
    }
}
