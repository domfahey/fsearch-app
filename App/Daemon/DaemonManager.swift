import FSearchKit
import Foundation
import ServiceManagement

/// Owns the daemon: use one that already answers, otherwise register the
/// bundled helper as a login item. Restarts it when asked.
@MainActor
final class DaemonManager: ObservableObject {
    enum State: Equatable { case checking, running(DaemonStatus), indexing, needsApproval, failed(String) }

    static let agentPlistName = "com.domfahey.fsearch.daemon.plist"
    @Published private(set) var state: State = .checking
    let client = DaemonClient(socketPath: AppState.socketPath)
    private var service: SMAppService { .agent(plistName: Self.agentPlistName) }

    /// True only when the app itself registered the daemon (never in test mode).
    var ownsDaemon: Bool { !AppState.testMode && service.status == .enabled }

    func start() async {
        if AppState.testMode { await refresh(); return }
        let answers = (try? await client.ping()) != nil
        if case .registerBundled = DaemonPlan.decide(existingAnswers: answers) {
            do { try service.register() } catch { state = .failed("Couldn't start the search helper: \(error.localizedDescription)"); return }
            if service.status == .requiresApproval { state = .needsApproval; return }
        }
        await refresh()
    }

    func refresh() async {
        for _ in 0..<50 {
            do { state = .running(try await client.status()); return }
            catch DaemonError.indexing { state = .indexing; return }
            catch { try? await Task.sleep(for: .milliseconds(200)) }
        }
        state = .failed("The search helper isn't answering.")
    }

    func restart() async {
        guard DaemonPlan.restartAction(owns: ownsDaemon) == .reregister else { await refresh(); return }
        try? await service.unregister()
        // Wait for the old daemon to go away before starting the new one.
        for _ in 0..<30 {
            if (try? await client.ping()) == nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        try? service.register()
        await refresh()
    }

    func saveNow() async { try? await client.save() }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
