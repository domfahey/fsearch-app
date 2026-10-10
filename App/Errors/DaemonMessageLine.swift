import AppKit
import FSearchKit
import SwiftUI

/// Under the search field: a bad query's one-line error, and the quiet recovery
/// work for a daemon that restarted or is still indexing. Results resume by themselves.
struct DaemonMessageLine: View {
    @Bindable var model: SearchModel
    @ObservedObject var daemon: DaemonManager
    @State private var host = HostWindow()

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
        .background(HostWindowReader(host: host))
        .onChange(of: model.phase) { _, p in
            switch p {
            case .results:
                MenuBarStatus.shared.restartBudget.reset()
                // Searches work, so a "failed" or "needs approval" warning is
                // stale (e.g. the daemon came back): re-check, at most every 5 s.
                let unhealthy = switch daemon.state {
                case .failed, .needsApproval: true
                default: false
                }
                if MenuBarStatus.shared.recoveryCheck.shouldRefresh(daemonUnhealthy: unhealthy) {
                    Task { await daemon.refresh() }
                }
            case .failed(.disconnected):
                // One budget per outage, shared across panel opens. `restart()`
                // re-registers only a daemon the app owns; a CLI daemon is just re-checked.
                guard MenuBarStatus.shared.restartBudget.spend() else { break }
                Task { await daemon.restart(); await model.refresh() }
            default: break
            }
        }
        .task(id: isIndexing) {
            // Poll every ~2 s (up to ~5 min of visible polling) until the daemon
            // answers or gives up. Paused while the panel is hidden.
            var tries = 0
            while isIndexing && tries < 150 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { break }
                guard host.window?.isVisible == true else { continue }
                await daemon.refresh()
                await model.refresh()
                tries += 1
            }
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
