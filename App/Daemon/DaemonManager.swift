import FSearchKit
import Foundation
import os

/// Owns the daemon: use one that already answers (or wait for a CLI login
/// agent's while it restarts), otherwise register the bundled helper as a
/// login item, once. Never stops or replaces a daemon it didn't start: only
/// a daemon it owns (our login item, holding the socket) is ever restarted.
@MainActor
final class DaemonManager: ObservableObject {
    enum State: Equatable { case checking, running(DaemonStatus), indexing, needsApproval, failed(String) }

    static let agentPlistName = "com.domfahey.fsearch.daemon.plist"
    /// The fsearch CLI's login agent (`fsearch install --login`). Only checked
    /// for existence; the app never touches ~/Library/LaunchAgents.
    static let cliAgentPlist = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/mt.nd.fsearch.plist")
    /// The state after timeouts, or a disconnect once the restarts ran out.
    nonisolated static let unresponsiveMessage = "The search helper stopped answering."
    /// Defaults key: the bundled helper's identity when it was last seen running.
    static let helperIdentityKey = "helperIdentity"

    @Published private(set) var state: State = .checking
    let client: any DaemonControl
    /// Our login item; nil in test mode, which never touches SMAppService.
    let service: HelperService?
    private let cliAgentInstalled: () -> Bool
    private let clock: DaemonClock
    private let socketHolder: () -> SocketHolder
    private let defaults: UserDefaults
    private let helperIdentity: () -> String?
    /// The one restart in flight; other callers wait for it instead of
    /// interleaving unregister/register with it.
    private var restartTask: Task<Void, Never>?
    /// Set when the menu sent the user to turn on Full Disk Access for our helper.
    private(set) var fullDiskAccessRestartArmed = false

    /// `socketHolder` says who holds the daemon's socket (see `SocketHolder`);
    /// `helperIdentity` names the bundled helper binary, to spot an app update.
    init(
        client: any DaemonControl, service: HelperService?,
        cliAgentInstalled: @escaping () -> Bool = { FileManager.default.fileExists(atPath: DaemonManager.cliAgentPlist.path) },
        clock: DaemonClock = .live,
        socketHolder: @escaping () -> SocketHolder = { .none },
        defaults: UserDefaults = AppDefaults.store,
        helperIdentity: @escaping () -> String? = { nil }
    ) {
        self.client = client
        self.service = service
        self.cliAgentInstalled = cliAgentInstalled
        self.clock = clock
        self.socketHolder = socketHolder
        self.defaults = defaults
        self.helperIdentity = helperIdentity
    }

    /// True only when our login item is enabled and no other daemon holds the
    /// socket (our helper yields to a CLI agent's daemon). Never in test mode.
    var ownsDaemon: Bool { DaemonPlan.owns(helperEnabled: service?.status == .enabled, holder: socketHolder()) }

    /// After timeouts, or a disconnect with no restarts left.
    var isUnresponsive: Bool { state == .failed(Self.unresponsiveMessage) }

    private func answers() async -> Bool { (try? await client.ping()) != nil }

    func start() async { await start(checkingForUpdate: true) }

    /// `checkingForUpdate` is false inside a restart, which must not restart again.
    private func start(checkingForUpdate: Bool) async {
        guard let service else { await refresh(); return }
        let existing = await answers()
        let cli = cliAgentInstalled()
        var plan = DaemonPlan.decide(existingAnswers: existing, ownStatus: service.status, cliAgentInstalled: cli)
        Log.daemon.info(
            "start: plan \(String(describing: plan), privacy: .public) (answers \(existing, privacy: .public), own \(String(describing: service.status), privacy: .public), cli agent \(cli, privacy: .public))"
        )
        if plan == .recheckThenRegister {
            // A daemon that is only restarting answers again within a few seconds.
            let deadline = clock.now().advanced(by: DaemonPlan.recheckWindow(cliAgentInstalled: cli))
            var answered = false
            while !answered && clock.now() < deadline {
                do { try await clock.sleep(.milliseconds(250)) } catch { return }
                answered = await answers()
            }
            plan = DaemonPlan.afterRecheck(existingAnswers: answered, ownStatus: service.status)
            Log.daemon.info("recheck: answered \(answered, privacy: .public), plan \(String(describing: plan), privacy: .public)")
        }
        var justRegistered = false
        if plan == .registerBundled {
            plan = register(service)
            justRegistered = true
        }
        switch plan {
        case .needsApproval: setState(.needsApproval)
        case .useExisting, .refreshOwn:
            await refresh()
            if checkingForUpdate { await restartIfUpdated(justRegistered: justRegistered) }
        case .recheckThenRegister, .registerBundled: break  // `register()` returned a failure state
        }
    }

    /// An app update replaces the helper binary, but launchd keeps the old one
    /// running: restart our own helper once when its identity changed.
    private func restartIfUpdated(justRegistered: Bool) async {
        let current = helperIdentity()
        let stored = defaults.string(forKey: Self.helperIdentityKey)
        let action = DaemonPlan.helperUpdate(owns: ownsDaemon, justRegistered: justRegistered, stored: stored, current: current)
        guard action != .nothing else { return }
        if action == .restartThenStore {
            Log.daemon.info("the bundled helper changed: restarting it once")
            await restart()
        }
        defaults.set(current, forKey: Self.helperIdentityKey)
    }

    /// Registers the helper; `.registerBundled` means it failed (state set).
    private func register(_ service: HelperService) -> DaemonPlan {
        do {
            try service.register()
            Log.daemon.info("register ok, status \(String(describing: service.status), privacy: .public)")
        } catch {
            Log.daemon.error(
                "register failed: \(error.localizedDescription, privacy: .private), status \(String(describing: service.status), privacy: .public)"
            )
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

    /// Restarts the daemon if it is ours; one at a time (a caller arriving
    /// while one runs waits for it). Someone else's daemon is only re-checked;
    /// with nothing answering and nothing ours, starts one as launch does.
    func restart() async {
        if let restartTask { await restartTask.value; return }
        let t = Task { @MainActor in
            await performRestart()
            restartTask = nil
        }
        restartTask = t
        await t.value
    }

    private func performRestart() async {
        guard let service else { await refresh(); return }
        let owns = ownsDaemon
        let answering = owns ? true : await answers()
        switch DaemonPlan.restartAction(owns: owns, answers: answering) {
        case .refreshOnly: await refresh(); return
        case .start:
            Log.daemon.info("restart: nothing answers and nothing is ours: starting")
            await start(checkingForUpdate: false); return
        case .reregister: break
        }
        Log.daemon.info("restart: re-registering")
        do { try await service.unregister() } catch {
            Log.daemon.error("unregister failed: \(error.localizedDescription, privacy: .private)")
        }
        // Wait for the old daemon to go away before starting the new one.
        for _ in 0..<30 {
            if !(await answers()) { break }
            try? await clock.sleep(.milliseconds(100))
        }
        switch register(service) {
        case .needsApproval: setState(.needsApproval)
        case .registerBundled: break  // failed; state already says why
        default:
            // The new process runs the bundled binary as it is now.
            if let id = helperIdentity() { defaults.set(id, forKey: Self.helperIdentityKey) }
            await refresh()
        }
    }

    /// The bundled helper binary's identity: the app build plus the binary's
    /// size and modification time. nil when it can't be read.
    nonisolated static func helperIdentity(helper: URL, build: String?) -> String? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: helper.path),
            let size = a[.size] as? NSNumber, let mtime = a[.modificationDate] as? Date
        else { return nil }
        return "\(build ?? "?"):\(size.int64Value):\(Int64(mtime.timeIntervalSince1970))"
    }

    /// This app's helper, Contents/Helpers/fsearch (see LaunchAgent.plist).
    nonisolated static func bundledHelperIdentity(bundle: Bundle = .main) -> String? {
        helperIdentity(
            helper: bundle.bundleURL.appendingPathComponent("Contents/Helpers/fsearch"),
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
    }

    /// Searches time out, or the restarts ran out: say so (menu bar and panel)
    /// until a refresh finds the daemon answering again.
    func markUnresponsive() { setState(.failed(Self.unresponsiveMessage)) }

    /// The menu's Full Disk Access item sent the user to System Settings for
    /// our helper; the daemon fixes its skip list when it starts.
    func armFullDiskAccessRestart() { fullDiskAccessRestartArmed = true }

    /// The app is active again: if armed, and our helper still runs without
    /// Full Disk Access, restart it once so a grant takes effect.
    func appBecameActive() async {
        guard fullDiskAccessRestartArmed else { return }
        fullDiskAccessRestartArmed = false
        let fullDiskAccess: Bool
        if case let .running(s) = state { fullDiskAccess = s.fullDiskAccess } else { return }
        guard restartAfterSettings(pressedTurnOn: true, owns: ownsDaemon, fullDiskAccess: fullDiskAccess) else { return }
        Log.daemon.info("back from System Settings: restarting the helper to pick up Full Disk Access")
        await restart()
    }

    func saveNow() async {
        do { try await client.save() } catch { Log.daemon.error("save failed: \(error.localizedDescription, privacy: .private)") }
    }

    func openLoginItems() { service?.openSystemSettingsLoginItems() }
}
