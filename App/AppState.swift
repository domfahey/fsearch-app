import FSearchKit
import SwiftUI

/// The app's shared state: the daemon, the search model, recents, the debug log and the action-error line.
///
/// Built once by ``live(options:)``; tests build their own with fakes through the initializer.
@MainActor
final class AppState: ObservableObject {
    /// How this process was launched.
    let options: LaunchOptions
    /// The daemon's lifecycle and state.
    let daemon: DaemonManager
    /// The search box's model.
    let search: SearchModel
    /// Files recently opened from the panel.
    let recents: Recents
    /// The debug search log; written only while ``debugMode`` is on.
    let log: SearchLog
    /// Debug mode: log searches and show timings and the debug windows.
    @AppStorage("debugMode") var debugMode = false
    /// Editor for content hits: `Editor.rawValue`, "" for none.
    @AppStorage("editor") var editorRaw = ""
    /// The chosen editor, if any.
    var editor: Editor? {
        get { Editor(rawValue: editorRaw) }
        set { editorRaw = newValue?.rawValue ?? "" }
    }
    /// Bumped whenever the recents may have changed (a file opened or trashed),
    /// so the panel re-reads `recents.paths`, which aren't observable themselves.
    @Published private(set) var recentsGeneration = 0
    /// Tells the panel to re-read the recents, dropping Recents' existence cache first.
    func recentsChanged() {
        recents.invalidate()
        recentsGeneration += 1
    }
    /// Opening a file makes it a recent.
    func openedRecent(_ path: String) {
        recents.opened(path)
        recentsChanged()
    }

    /// One-line failure from a file action, shown in the panel footer for a few seconds.
    @Published var actionError: String?
    private var errorClear: Task<Void, Never>?
    /// How long an action error stays up.
    var actionErrorDuration: Duration = .seconds(5)
    /// Brought back when an action fails while it is hidden; put away after an action.
    var panel: PanelHost = PanelController.shared

    /// Bumped by every error, so a caller can tell whether its action reported one.
    private(set) var actionErrorCount = 0

    /// Shows a one-line error in the panel footer, bringing the panel back if an action already hid it.
    func showActionError(_ message: String) {
        actionErrorCount += 1
        actionError = message
        // An action that sends you to another app hides the launcher; if it fails
        // afterwards, bring the launcher back (query and selection resume) so the error is seen.
        if !panel.isVisible { panel.show(app: self) }
        errorClear?.cancel()
        let duration = actionErrorDuration
        errorClear = Task { [weak self] in
            try? await Task.sleep(for: duration)
            if !Task.isCancelled { self?.actionError = nil }
        }
    }

    /// The running app: real daemon connections, real login item (none in test mode).
    ///
    /// - Parameter options: The launch options.
    static func live(options: LaunchOptions = .current) -> AppState {
        AppState(
            options: options, defaults: options.testMode ? AppDefaults.store : .standard,
            helper: options.testMode ? nil : SMAppHelperService(),
            // Two connections: names and content never wait on each other.
            names: DaemonClient(socketPath: options.socketPath),
            content: DaemonClient(socketPath: options.socketPath),
            control: DaemonClient(socketPath: options.socketPath),
            socketHolder: {
                SocketHolder.read(dataDir: DebugFormat.dataDir(socketPath: options.socketPath), bundlePath: Bundle.main.bundlePath)
            },
            helperIdentity: { DaemonManager.bundledHelperIdentity() },
            fullDiskAccessGranted: { DaemonManager.appHasFullDiskAccess() })
    }

    /// Creates the state from its parts.
    ///
    /// - Parameters:
    ///   - options: The launch options.
    ///   - defaults: Where recents and settings live.
    ///   - helper: The helper's login item, or nil in test mode.
    ///   - names: The connection for name searches.
    ///   - content: The connection for content searches.
    ///   - control: The connection for status and "Save Now".
    ///   - clock: Timers for the daemon wait loops.
    ///   - cliAgentInstalled: Whether the CLI's login agent exists.
    ///   - socketHolder: Who holds the daemon's socket (decides ``DaemonManager/ownsDaemon``).
    ///   - helperIdentity: The bundled helper binary's identity, to spot an app update.
    ///   - fullDiskAccessGranted: Whether FSearch has Full Disk Access now.
    init(
        options: LaunchOptions, defaults: UserDefaults, helper: HelperService?,
        names: SearchBackend, content: SearchBackend, control: any DaemonControl,
        clock: DaemonClock = .live,
        cliAgentInstalled: @escaping () -> Bool = { FileManager.default.fileExists(atPath: DaemonManager.cliAgentPlist.path) },
        socketHolder: @escaping () -> SocketHolder = { .none },
        helperIdentity: @escaping () -> String? = { nil },
        fullDiskAccessGranted: @escaping () -> Bool = { false }
    ) {
        self.options = options
        daemon = DaemonManager(
            client: control, service: helper, cliAgentInstalled: cliAgentInstalled, clock: clock,
            socketHolder: socketHolder, defaults: defaults, helperIdentity: helperIdentity,
            fullDiskAccessGranted: fullDiskAccessGranted)
        search = SearchModel(names: names, content: content)
        recents = Recents(defaults: defaults)
        log = SearchLog(file: options.searchLogFile)
        _debugMode = AppStorage(wrappedValue: false, "debugMode", store: defaults)
        _editorRaw = AppStorage(wrappedValue: "", "editor", store: defaults)
        search.onSearched = { [weak self] e in
            guard let self, self.debugMode else { return }
            self.log.append(e, at: Date())
        }
        search.onSettled = { [weak self] phase in self?.searchSettled(phase) }
    }

    /// The restart budget and recovery check (shared by every panel open).
    var status: MenuBarStatus = .shared

    /// Handles every finished search; wired to ``SearchModel/onSettled``.
    ///
    /// Results refill the restart budget and re-check a
    /// daemon marked down; a dropped connection restarts it, once per unit of
    /// the outage's budget (each restart searches again, and may fail again).
    ///
    /// - Parameter phase: How the search ended.
    func searchSettled(_ phase: SearchPhase) {
        guard !daemon.recoverySuspended else { return }
        switch phase {
        case .results:
            status.restartBudget.reset()
            // Searches work, so a "failed" or "needs approval" warning is
            // stale (e.g. the daemon came back): re-check, at most every 5 s.
            // "Isn't answering" is plainly wrong now: re-check at once.
            let unhealthy =
                switch daemon.state {
                case .failed, .needsApproval: true
                default: false
                }
            if daemon.isUnresponsive || status.recoveryCheck.shouldRefresh(daemonUnhealthy: unhealthy) {
                Task { await daemon.refresh() }
            }
        case .failed(.disconnected):
            // `restart()` re-registers only a daemon the app owns; a CLI daemon is just re-checked.
            // Out of restarts: say the helper isn't answering, not "Starting search…".
            guard status.restartBudget.spend() else { daemon.markUnresponsive(); return }
            Task {
                await daemon.restart()
                guard !daemon.recoverySuspended else { return }
                await search.refresh()
            }
        case .failed(.timeout):
            daemon.markUnresponsive()
        default: break
        }
    }
}
