import FSearchKit
import Foundation
import ServiceManagement

/// Owns the daemon: use one that already answers (or a CLI login agent's,
/// even while it restarts), otherwise register the bundled helper as a login
/// item, once. Never stops or replaces a daemon it didn't start.
@MainActor
final class DaemonManager: ObservableObject {
    enum State: Equatable { case checking, running(DaemonStatus), indexing, needsApproval, failed(String) }

    static let agentPlistName = "com.domfahey.fsearch.daemon.plist"
    /// The fsearch CLI's login agent (`fsearch install --login`). Only checked
    /// for existence; the app never touches ~/Library/LaunchAgents.
    static let cliAgentPlist = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/mt.nd.fsearch.plist")
    @Published private(set) var state: State = .checking
    let client = DaemonClient(socketPath: AppState.socketPath)
    private var service: SMAppService { .agent(plistName: Self.agentPlistName) }

    /// True only when the app itself registered the daemon (never in test mode).
    var ownsDaemon: Bool { !AppState.testMode && service.status == .enabled }

    /// Our helper's status; nil in test mode, which never touches SMAppService.
    private var ownStatus: DaemonPlan.ServiceStatus? {
        if AppState.testMode { return nil }
        return switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        default: .notRegistered
        }
    }

    private func answers() async -> Bool { (try? await client.ping()) != nil }

    func start() async {
        if AppState.testMode { await refresh(); return }
        let cli = FileManager.default.fileExists(atPath: Self.cliAgentPlist.path)
        var plan = DaemonPlan.decide(existingAnswers: await answers(), ownStatus: ownStatus ?? .notRegistered, cliAgentInstalled: cli)
        if plan == .recheckThenRegister {
            // A daemon that is only restarting answers again within a few seconds.
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: DaemonPlan.recheckWindow)
            var answered = false
            while !answered && clock.now < deadline {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                answered = await answers()
            }
            plan = DaemonPlan.afterRecheck(existingAnswers: answered)
        }
        if plan == .registerBundled { plan = register() }
        switch plan {
        case .needsApproval: state = .needsApproval
        case .useExisting, .refreshOwn: await refresh()
        case .recheckThenRegister, .registerBundled: break // `register()` returned a failure state
        }
    }

    /// Registers the helper; `.registerBundled` means it failed (state set).
    private func register() -> DaemonPlan {
        do { try service.register() } catch {
            // Already waiting for approval is not an error worth showing as one.
            if service.status == .requiresApproval { return .needsApproval }
            state = .failed("Couldn't start the search helper: \(error.localizedDescription)")
            return .registerBundled
        }
        return DaemonPlan.afterRegister(ownStatus: ownStatus ?? .notRegistered)
    }

    /// A cancelled caller (e.g. a closed window) leaves the state alone.
    func refresh() async {
        for _ in 0..<50 {
            if Task.isCancelled { return }
            do { state = .running(try await client.status()); return }
            catch DaemonError.indexing { state = .indexing; return }
            catch is CancellationError { return }
            catch {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
        if Task.isCancelled { return }
        switch DaemonPlan.noAnswer(wasNeedingApproval: state == .needsApproval, ownStatus: ownStatus) {
        case .needsApproval: state = .needsApproval
        case .failed: state = .failed("The search helper isn't answering.")
        }
    }

    func restart() async {
        guard DaemonPlan.restartAction(owns: ownsDaemon) == .reregister else { await refresh(); return }
        try? await service.unregister()
        // Wait for the old daemon to go away before starting the new one.
        for _ in 0..<30 {
            if !(await answers()) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        switch register() {
        case .needsApproval: state = .needsApproval
        case .registerBundled: break // failed; state already says why
        default: await refresh()
        }
    }

    func saveNow() async { try? await client.save() }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
