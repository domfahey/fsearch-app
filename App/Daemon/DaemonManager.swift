import FSearchKit
import Foundation
import os

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
    let service: HelperService?
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
        let existing = await answers()
        let cli = cliAgentInstalled()
        var plan = DaemonPlan.decide(existingAnswers: existing, ownStatus: service.status, cliAgentInstalled: cli)
        Log.daemon.info("start: plan \(String(describing: plan), privacy: .public) (answers \(existing, privacy: .public), own \(String(describing: service.status), privacy: .public), cli agent \(cli, privacy: .public))")
        if plan == .recheckThenRegister {
            // A daemon that is only restarting answers again within a few seconds.
            let deadline = clock.now().advanced(by: DaemonPlan.recheckWindow)
            var answered = false
            while !answered && clock.now() < deadline {
                do { try await clock.sleep(.milliseconds(250)) } catch { return }
                answered = await answers()
            }
            plan = DaemonPlan.afterRecheck(existingAnswers: answered)
            Log.daemon.info("recheck: answered \(answered, privacy: .public), plan \(String(describing: plan), privacy: .public)")
        }
        if plan == .registerBundled { plan = register(service) }
        switch plan {
        case .needsApproval: setState(.needsApproval)
        case .useExisting, .refreshOwn: await refresh()
        case .recheckThenRegister, .registerBundled: break // `register()` returned a failure state
        }
    }

    /// Registers the helper; `.registerBundled` means it failed (state set).
    private func register(_ service: HelperService) -> DaemonPlan {
        do {
            try service.register()
            Log.daemon.info("register ok, status \(String(describing: service.status), privacy: .public)")
        } catch {
            Log.daemon.error("register failed: \(error.localizedDescription, privacy: .public), status \(String(describing: service.status), privacy: .public)")
            // Already waiting for approval is not an error worth showing as one.
            if service.status == .requiresApproval { return .needsApproval }
            setState(.failed("Couldn't start the search helper: \(error.localizedDescription)"))
            return .registerBundled
        }
        return DaemonPlan.afterRegister(ownStatus: service.status)
    }

    /// A cancelled caller (e.g. a closed window) leaves the state alone.
    func refresh() async {
        for _ in 0..<50 {
            if Task.isCancelled { return }
            do { setState(.running(try await client.status())); return }
            catch DaemonError.indexing { setState(.indexing); return }
            catch is CancellationError { return }
            catch {
                do { try await clock.sleep(.milliseconds(200)) } catch { return }
            }
        }
        if Task.isCancelled { return }
        switch DaemonPlan.noAnswer(wasNeedingApproval: state == .needsApproval, ownStatus: service?.status) {
        case .needsApproval: setState(.needsApproval)
        case .failed: setState(.failed("The search helper isn't answering."))
        }
    }

    /// Logs changes only; routine polls that find the same state stay quiet.
    private func setState(_ new: State) {
        if new != state {
            let old = Self.name(state), now = Self.name(new)
            Log.daemon.info("state \(old, privacy: .public) -> \(now, privacy: .public)")
        }
        state = new
    }

    private static func name(_ s: State) -> String {
        switch s {
        case .checking: "checking"
        case .running: "running"
        case .indexing: "indexing"
        case .needsApproval: "needsApproval"
        case .failed: "failed"
        }
    }

    func restart() async {
        guard let service, DaemonPlan.restartAction(owns: ownsDaemon) == .reregister else { await refresh(); return }
        Log.daemon.info("restart: re-registering")
        do { try await service.unregister() } catch {
            Log.daemon.error("unregister failed: \(error.localizedDescription, privacy: .public)")
        }
        // Wait for the old daemon to go away before starting the new one.
        for _ in 0..<30 {
            if !(await answers()) { break }
            try? await clock.sleep(.milliseconds(100))
        }
        switch register(service) {
        case .needsApproval: setState(.needsApproval)
        case .registerBundled: break // failed; state already says why
        default: await refresh()
        }
    }

    func saveNow() async {
        do { try await client.save() } catch { Log.daemon.error("save failed: \(error.localizedDescription, privacy: .public)") }
    }

    func openLoginItems() { service?.openSystemSettingsLoginItems() }
}
