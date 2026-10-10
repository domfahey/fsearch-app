import AppKit
import FSearchKit
import SwiftUI

/// Under the search field: a bad query's one-line error, and the quiet recovery
/// work for a daemon that restarted or is still indexing. Results resume by themselves.
struct DaemonMessageLine: View {
    @Bindable var model: SearchModel
    @ObservedObject var daemon: DaemonManager
    @State private var host = HostWindow()
    /// Bumped each time the panel comes on screen.
    @State private var shown = 0

    private var isIndexing: Bool {
        if daemon.state == .indexing { return true }
        switch model.phase {
        case .indexing, .failed(.indexing): return true
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Always present (a background on an empty Group is never created,
            // which left `host.window` nil and the indexing poll idle forever).
            HostWindowReader(host: host).frame(width: 0, height: 0)
            if case let .failed(.daemon(msg)) = model.phase {
                Text(msg).font(.caption).foregroundStyle(.red).lineLimit(2)
                    .padding(.horizontal, 16).padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("queryError")
            }
        }
        // Restarts and recovery checks run in AppState.searchSettled, on every
        // finished search, not on phase changes this view happens to render.
        // Showing the panel again restarts a poll that stopped while hidden.
        .task(id: PollKey(indexing: isIndexing, shown: shown)) {
            let host = host
            await Self.pollWhileIndexing(
                isIndexing: { isIndexing }, visible: { host.window?.isVisible == true },
                sleep: { try await Task.sleep(for: .seconds(2)) },
                step: {
                    await daemon.refresh()
                    await model.refresh()
                })
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { note in
            guard let w = note.object as? NSWindow, w === host.window, w.occlusionState.contains(.visible) else { return }
            shown &+= 1
        }
    }

    private struct PollKey: Equatable {
        let indexing: Bool
        let shown: Int
    }

    /// Polls every ~2 s, up to `maxTries` times, until the daemon is done
    /// indexing. Stops as soon as the panel is hidden (the view starts it
    /// again when the panel shows), so a hidden panel never polls forever.
    static func pollWhileIndexing(
        isIndexing: () -> Bool, visible: () -> Bool, sleep: () async throws -> Void, step: () async -> Void,
        maxTries: Int = 150
    ) async {
        var tries = 0
        while isIndexing() && tries < maxTries && !Task.isCancelled {
            try? await sleep()
            if Task.isCancelled || !visible() { return }
            await step()
            tries += 1
        }
    }
}

/// The window hosting a view, held weakly; reading it doesn't redraw anything.
final class HostWindow {
    weak var window: NSWindow?
}

private struct HostWindowReader: NSViewRepresentable {
    let host: HostWindow

    func makeNSView(context: Context) -> NSView {
        let view = WindowTrackingView()
        view.host = host
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowTrackingView: NSView {
        var host: HostWindow?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            host?.window = window
        }
    }
}
