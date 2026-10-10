import FSearchKit
import Foundation

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
    let client: any DaemonControl
    /// Our login item; nil in test mode, which never touches SMAppService.
    private let service: HelperService?
    private let cliAgentInstalled: () -> Bool
    private let clock: DaemonClock

    init(client: any DaemonControl, service: HelperService?,
         cliAgentInstalled: @escaping () -> Bool = { FileManager.default.fileExists(atPath: DaemonManager.cliAgentPlist.path) },
         clock: DaemonClock = .live) {
        self.client = client
        self.service = service
        self.cliAgentInstalled = cliAgentInstalled
        self.clock = clock
    }

    /// True only when the app itself registered the daemon (never in test mode).
    var ownsDaemon: Bool { service?.status == .enabled }

    private func answers() async -> Bool { (try? await client.ping()) != nil }

    func start() async {
        guard let service else { await refresh(); return }
        var plan = DaemonPlan.decide(existingAnswers: await answers(), ownStatus: service.status, cliAgentInstalled: cliAgentInstalled())
        if plan == .recheckThenRegister {
            // A daemon that is only restarting answers again within a few seconds.
            let deadline = clock.now().advanced(by: DaemonPlan.recheckWindow)
            var answered = false
            while !answered && clock.now() < deadline {
                do { try await clock.sleep(.milliseconds(250)) } catch { return }
                answered = await answers()
            }
            plan = DaemonPlan.afterRecheck(existingAnswers: answered)
        }
        if plan == .registerBundled { plan = register(service) }
        switch plan {
        case .needsApproval: state = .needsApproval
        case .useExisting, .refreshOwn: await refresh()
        case .recheckThenRegister, .registerBundled: break // `register()` returned a failure state
        }
    }

    /// Registers the helper; `.registerBundled` means it failed (state set).
    private func register(_ service: HelperService) -> DaemonPlan {
        do { try service.register() } catch {
            // Already waiting for approval is not an error worth showing as one.
            if service.status == .requiresApproval { return .needsApproval }
            state = .failed("Couldn't start the search helper: \(error.localizedDescription)")
            return .registerBundled
        }
        return DaemonPlan.afterRegister(ownStatus: service.status)
    }

    /// A cancelled caller (e.g. a closed window) leaves the state alone.
    func refresh() async {
        for _ in 0..<50 {
            if Task.isCancelled { return }
            do { state = .running(try await client.status()); return }
            catch DaemonError.indexing { state = .indexing; return }
            catch is CancellationError { return }
            catch {
                do { try await clock.sleep(.milliseconds(200)) } catch { return }
            }
        }
        if Task.isCancelled { return }
        switch DaemonPlan.noAnswer(wasNeedingApproval: state == .needsApproval, ownStatus: service?.status) {
        case .needsApproval: state = .needsApproval
        case .failed: state = .failed("The search helper isn't answering.")
        }
    }

    func restart() async {
        guard let service, DaemonPlan.restartAction(owns: ownsDaemon) == .reregister else { await refresh(); return }
        try? await service.unregister()
        // Wait for the old daemon to go away before starting the new one.
        for _ in 0..<30 {
            if !(await answers()) { break }
            try? await clock.sleep(.milliseconds(100))
        }
        switch register(service) {
        case .needsApproval: state = .needsApproval
        case .registerBundled: break // failed; state already says why
        default: await refresh()
        }
    }

    func saveNow() async { try? await client.save() }

    func openLoginItems() { service?.openSystemSettingsLoginItems() }
}
