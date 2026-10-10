import FSearchKit
import Foundation
import os

/// Owns the daemon: use one that already answers (or a CLI login agent's,
/// even while it restarts), otherwise register the bundled helper as a login
/// item, once. Never stops or replaces a daemon it didn't start.
///
/// Ownership: the app "owns" the daemon only when its own helper is enabled (``ownsDaemon``).
/// Everything that stops or restarts a daemon is gated on that, because a daemon started from the
/// CLI (or a test daemon) belongs to the user and may be serving other tools. For those the app
/// only reads its state. In test mode there is no `service`, so the app never owns anything.
///
/// ``state`` is what the menu bar, panel and onboarding observe.
@MainActor
final class DaemonManager: ObservableObject {
    /// What the app knows about the daemon.
    enum State: Equatable {
        /// Not asked yet, or asking.
        case checking
        /// Answering, with its status.
        case running(DaemonStatus)
        /// Answering, but still building its first index.
        case indexing
        /// The helper is registered but waits for approval in Login Items.
        case needsApproval
        /// Not answering; the text says why.
        case failed(String)
    }

    /// The launch-agent plist inside the app bundle that SMAppService registers.
    static let agentPlistName = "com.domfahey.fsearch.daemon.plist"
    /// The fsearch CLI's login agent (`fsearch install --login`). Only checked
    /// for existence; the app never touches ~/Library/LaunchAgents.
    static let cliAgentPlist = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/mt.nd.fsearch.plist")
    /// The daemon's state; updated only through `setState`.
    @Published private(set) var state: State = .checking
    /// The connection used for status checks and "Save Now".
    let client: any DaemonControl
    /// Our login item; nil in test mode, which never touches SMAppService.
    let service: HelperService?
    /// Whether the CLI's login agent plist exists (injected for tests).
    private let cliAgentInstalled: () -> Bool
    /// Sleeps and time (injected so tests don't wait).
    private let clock: DaemonClock

    /// Creates a manager.
    ///
    /// - Parameters:
    ///   - client: The connection to the daemon.
    ///   - service: The helper's login item, or nil in test mode (SMAppService is never touched).
    ///   - cliAgentInstalled: Whether a CLI login agent exists.
    ///   - clock: Timers for the wait loops.
    init(
        client: any DaemonControl, service: HelperService?,
        cliAgentInstalled: @escaping () -> Bool = { FileManager.default.fileExists(atPath: DaemonManager.cliAgentPlist.path) },
        clock: DaemonClock = .live
    ) {
        self.client = client
        self.service = service
        self.cliAgentInstalled = cliAgentInstalled
        self.clock = clock
    }

    /// True only when the app itself registered the daemon (never in test mode).
    var ownsDaemon: Bool { service?.status == .enabled }

    /// Whether the daemon answers a ping now.
    private func answers() async -> Bool { (try? await client.ping()) != nil }

    /// Chooses and carries out the launch plan (see ``DaemonPlan``), leaving ``state`` set.
    ///
    /// A daemon that merely restarts gets a short recheck window before the bundled helper is registered. Returns early, without
    /// changing state, if the task is cancelled during that wait.
    func start() async {
        guard let service else { await refresh(); return }
        let existing = await answers()
        let cli = cliAgentInstalled()
        var plan = DaemonPlan.decide(existingAnswers: existing, ownStatus: service.status, cliAgentInstalled: cli)
        Log.daemon.info(
            "start: plan \(String(describing: plan), privacy: .public) (answers \(existing, privacy: .public), own \(String(describing: service.status), privacy: .public), cli agent \(cli, privacy: .public))"
        )
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
        case .recheckThenRegister, .registerBundled: break  // `register()` returned a failure state
        }
    }

    /// Registers the helper; `.registerBundled` means it failed (state set).
    private func register(_ service: HelperService) -> DaemonPlan {
        do {
            try service.register()
            Log.daemon.info("register ok, status \(String(describing: service.status), privacy: .public)")
        } catch {
            Log.daemon.error(
                "register failed: \(error.localizedDescription, privacy: .public), status \(String(describing: service.status), privacy: .public)"
            )
            // Already waiting for approval is not an error worth showing as one.
            if service.status == .requiresApproval { return .needsApproval }
            setState(.failed("Couldn't start the search helper: \(error.localizedDescription)"))
            return .registerBundled
        }
        return DaemonPlan.afterRegister(ownStatus: service.status)
    }

    /// Asks the daemon for its status until it answers, then sets ``state``.
    ///
    /// Tries 50 times, 200 ms apart (about 10 s), so a daemon that is starting up has time to listen. After that, the state is
    /// `.failed`, or `.needsApproval` if the helper is waiting for approval. A cancelled caller (e.g. a closed window)
    /// leaves the state alone.
    func refresh() async {
        for _ in 0..<50 {
            if Task.isCancelled { return }
            do { setState(.running(try await client.status())); return } catch DaemonError.indexing {
                setState(.indexing); return
            } catch is CancellationError { return } catch {
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

    /// Restarts the daemon if the app owns it; otherwise only re-reads its state.
    ///
    /// Only an owned helper is unregistered and registered again. A daemon the app didn't start (the CLI's, a test daemon)
    /// may be in use by other tools, so it is never stopped, and "restart" means "look again".
    func restart() async {
        guard let service, DaemonPlan.restartAction(owns: ownsDaemon) == .reregister else { await refresh(); return }
        Log.daemon.info("restart: re-registering")
        do { try await service.unregister() } catch {
            Log.daemon.error("unregister failed: \(error.localizedDescription, privacy: .public)")
        }
        // Wait (up to 3 s) for the old daemon to stop answering before registering the new one, so the new one doesn't find the
        // old one still on the socket.
        for _ in 0..<30 {
            if !(await answers()) { break }
            try? await clock.sleep(.milliseconds(100))
        }
        switch register(service) {
        case .needsApproval: setState(.needsApproval)
        case .registerBundled: break  // failed; state already says why
        default: await refresh()
        }
    }

    /// Asks the daemon to compact and save its index now; a failure is only logged.
    func saveNow() async {
        do { try await client.save() } catch { Log.daemon.error("save failed: \(error.localizedDescription, privacy: .public)") }
    }

    /// Opens System Settings at Login Items, where a pending helper is approved.
    func openLoginItems() { service?.openSystemSettingsLoginItems() }
}
