import FSearchKit
import SwiftUI

/// The app's shared state: the daemon, the search model, recents, the debug log and the action-error line.
///
/// Built once by ``live(options:)``; tests build their own with fakes through the initializer.
@MainActor
final class AppState: ObservableObject {
    /// How this process was launched.
    let options: LaunchOptions
    /// Backing defaults store for settings, recents, saved searches, and window column layout.
    let defaults: UserDefaults
    /// The daemon's lifecycle and state.
    let daemon: DaemonManager
    /// The search box's model.
    let search: SearchModel
    /// Files recently opened from the panel.
    let recents: Recents
    /// User-created saved searches shared across Everything-style search windows.
    let savedSearches: SavedSearchStore
    /// The debug search log; written only while ``debugMode`` is on.
    let log: SearchLog
    /// Creates independent `(names, content)` backends for each Everything-style search window.
    private let makeWindowBackends: () -> (names: SearchBackend, content: SearchBackend)
    /// Debug mode: log searches and show timings and the debug windows.
    @AppStorage("debugMode") var debugMode = false
    /// Editor for content hits: `Editor.rawValue`, "" for none.
    @AppStorage("editor") var editorRaw = ""
    /// Default search UI (`SearchInterface.rawValue`): `"panel"` (classic) or `"window"` (Everything-style).
    @AppStorage(SearchInterface.storageKey) var searchInterfaceRaw = SearchInterface.panel.rawValue
    /// Lets the Shortcuts "Search Files" action search inside files and find definitions (off by default).
    @AppStorage(SearchFilesIntent.allowContentSearchKey) var allowShortcutsContentSearch = false
    /// The chosen editor, if any.
    var editor: Editor? {
        get { Editor(rawValue: editorRaw) }
        set { editorRaw = newValue?.rawValue ?? "" }
    }
    /// The preferred search interface opened by the global shortcut, menu-bar **Search…**, reopen, and `fsearch://` links.
    var searchInterface: SearchInterface {
        get { SearchInterface.resolve(searchInterfaceRaw) }
        set { searchInterfaceRaw = newValue.rawValue }
    }
    /// Bumped whenever the recents may have changed (a file opened or trashed),
    /// so the panel re-reads `recents.paths`, which aren't observable themselves.
    @Published private(set) var recentsGeneration = 0
    /// Bumped whenever user-saved searches change, so every open search window refreshes its sidebar.
    @Published private(set) var savedSearchesGeneration = 0
    /// Tells open search windows to reload `savedSearches`.
    func savedSearchesChanged() {
        savedSearchesGeneration += 1
    }
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
        // The control connection names its daemon by code signature (ownership, Index Details).
        let control = DaemonClient(socketPath: options.socketPath, identifyPeer: .live(bundlePath: Bundle.main.bundlePath))
        return AppState(
            options: options, defaults: options.testMode ? AppDefaults.store : .standard,
            helper: options.testMode ? nil : SMAppHelperService(),
            // Three connections: names, content, and control never wait on each other.
            names: DaemonClient(socketPath: options.socketPath),
            content: DaemonClient(socketPath: options.socketPath),
            control: control,
            makeWindowBackends: {
                (DaemonClient(socketPath: options.socketPath), DaemonClient(socketPath: options.socketPath))
            },
            socketHolder: {
                SocketHolder.read(dataDir: DebugFormat.dataDir(socketPath: options.socketPath), bundlePath: Bundle.main.bundlePath)
            },
            peer: { control.peer },
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
    ///   - socketHolder: Who holds the daemon's socket per socket.lock (a fallback for `peer`).
    ///   - peer: The connected daemon by code signature (decides ``DaemonManager/ownsDaemon`` when known).
    ///   - helperIdentity: The bundled helper binary's identity, to spot an app update.
    ///   - fullDiskAccessGranted: Whether FSearch has Full Disk Access now.
    init(
        options: LaunchOptions, defaults: UserDefaults, helper: HelperService?,
        names: SearchBackend, content: SearchBackend, control: any DaemonControl,
        clock: DaemonClock = .live,
        makeWindowBackends: (() -> (names: SearchBackend, content: SearchBackend))? = nil,
        cliAgentInstalled: @escaping () -> Bool = { FileManager.default.fileExists(atPath: DaemonManager.cliAgentPlist.path) },
        socketHolder: @escaping () -> SocketHolder = { .none },
        peer: @escaping () -> SocketHolder? = { nil },
        helperIdentity: @escaping () -> String? = { nil },
        fullDiskAccessGranted: @escaping () -> Bool = { false }
    ) {
        self.options = options
        self.defaults = defaults
        daemon = DaemonManager(
            client: control, service: helper, cliAgentInstalled: cliAgentInstalled, clock: clock,
            socketHolder: socketHolder, peer: peer, defaults: defaults, helperIdentity: helperIdentity,
            fullDiskAccessGranted: fullDiskAccessGranted)
        search = SearchModel(names: names, content: content)
        recents = Recents(defaults: defaults)
        savedSearches = SavedSearchStore(defaults: defaults)
        log = SearchLog(file: options.searchLogFile)
        self.makeWindowBackends = makeWindowBackends ?? { (names, content) }
        _debugMode = AppStorage(wrappedValue: false, "debugMode", store: defaults)
        _editorRaw = AppStorage(wrappedValue: "", "editor", store: defaults)
        _searchInterfaceRaw = AppStorage(wrappedValue: SearchInterface.panel.rawValue, SearchInterface.storageKey, store: defaults)
        _allowShortcutsContentSearch = AppStorage(wrappedValue: false, SearchFilesIntent.allowContentSearchKey, store: defaults)
        search.onSearched = { [weak self] e in
            guard let self, self.debugMode else { return }
            self.log.appendAsync(e, at: Date())
        }
        search.onSettled = { [weak self] phase in self?.searchSettled(phase) }
    }

    /// Creates an independent ``SearchWindowModel`` wired to this app's debug search log and daemon recovery.
    func makeSearchWindowModel() -> SearchWindowModel {
        let pair = makeWindowBackends()
        let model = SearchWindowModel(names: pair.names, content: pair.content)
        model.onSearched = { [weak self] entry in
            guard let self, self.debugMode else { return }
            self.log.appendAsync(entry, at: Date())
        }
        model.onSettled = { [weak self, weak model] phase in
            guard let model else { return }
            self?.searchSettled(phase, recoveryKey: ObjectIdentifier(model), refreshOnRecovery: { [weak model] in await model?.refresh() })
        }
        return model
    }

    /// Toggles the user's preferred search interface (global shortcut).
    func togglePrimarySearch(panel: PanelHost = PanelController.shared, windows: SearchWindowManager = .shared) {
        switch searchInterface {
        case .panel:
            panel.toggle(app: self)
        case .window:
            windows.toggle(app: self)
        }
    }

    /// Opens or brings forward the user's preferred search interface (menu-bar **Search…**).
    ///
    /// Unlike the global shortcut toggle, clicking **Search…** from the menu bar always surfaces search
    /// rather than hiding an already-open Search Window.
    func openPrimarySearch(panel: PanelHost = PanelController.shared, windows: SearchWindowManager = .shared) {
        switch searchInterface {
        case .panel:
            panel.toggle(app: self)
        case .window:
            _ = windows.activateOrOpen(app: self)
        }
    }

    /// Brings forward or opens the user's preferred search interface when another launch hands over to this instance.
    func reopenPrimarySearch(panel: PanelHost = PanelController.shared, windows: SearchWindowManager = .shared) {
        switch searchInterface {
        case .panel:
            if !panel.isVisible { panel.showExternally(app: self) }
        case .window:
            windows.activateOrOpen(app: self)
        }
    }

    /// Opens an incoming `fsearch://` search URL in either its explicit `ui=` target or the user's preferred interface.
    func openSearchURL(_ search: SearchURL, panel: PanelHost = PanelController.shared, windows: SearchWindowManager = .shared) {
        switch search.interface ?? searchInterface {
        case .panel:
            panel.show(app: self, search: search)
        case .window:
            if panel.isVisible { panel.hide(returnFocus: false) }
            _ = windows.openWindow(app: self, initialQuery: search.query, initialMode: search.mode)
        }
    }

    /// The restart budget and recovery check (shared by every panel open).
    var status: MenuBarStatus = .shared
    /// Coalesces disconnect-driven restarts so rapid failures don't burn extra budget tokens.
    private var disconnectRestartTask: Task<Void, Never>?
    /// Originating window models (keyed by identity so rapid failures from one window coalesce) waiting to refresh after recovery.
    private var pendingRecoveryRefreshes: [ObjectIdentifier: @MainActor () async -> Void] = [:]
    /// Coalesces recovery refreshes while `daemon.isUnresponsive`.
    private var recoveryRefreshTask: Task<Void, Never>?

    /// Handles every finished search; wired to ``SearchModel/onSettled`` and ``SearchWindowModel/onSettled``.
    ///
    /// Results refill the restart budget and re-check a
    /// daemon marked down; a dropped connection restarts it, once per unit of
    /// the outage's budget (each restart searches again, and may fail again).
    ///
    /// - Parameters:
    ///   - phase: How the search ended.
    ///   - recoveryKey: Identity key used to deduplicate pending window recovery callbacks.
    ///   - refreshOnRecovery: Optional callback for an originating search window to refresh after recovery.
    func searchSettled(
        _ phase: SearchPhase, recoveryKey: ObjectIdentifier? = nil, refreshOnRecovery: (@MainActor () async -> Void)? = nil
    ) {
        guard !daemon.recoverySuspended else { return }
        switch phase {
        case .results:
            status.restartBudget.reset()
            // Searches work, so a "failed" or "needs approval" warning is
            // stale (e.g. the daemon came back): re-check, at most every 5 s.
            // "Isn't answering" is plainly wrong now: re-check at once (coalesced).
            let unhealthy =
                switch daemon.state {
                case .failed, .needsApproval: true
                default: false
                }
            if recoveryRefreshTask == nil, daemon.isUnresponsive || status.recoveryCheck.shouldRefresh(daemonUnhealthy: unhealthy) {
                recoveryRefreshTask = Task { [weak self] in
                    defer { self?.recoveryRefreshTask = nil }
                    await self?.daemon.refresh()
                }
            }
        case .failed(.disconnected):
            if let recoveryKey, let refreshOnRecovery { pendingRecoveryRefreshes[recoveryKey] = refreshOnRecovery }
            // A restart is already running (and will refresh all waiting searches when it finishes): don't burn another token.
            if daemon.isRestarting || disconnectRestartTask != nil { return }
            // `restart()` re-registers only a daemon the app owns; a CLI daemon is just re-checked.
            // Out of restarts: say the helper isn't answering, not "Starting search…".
            guard status.restartBudget.spend() else {
                pendingRecoveryRefreshes.removeAll()
                daemon.markUnresponsive()
                return
            }
            disconnectRestartTask = Task { [weak self] in
                await self?.daemon.restart()
                self?.disconnectRestartTask = nil
                guard let self else { return }
                let pending = Array(self.pendingRecoveryRefreshes.values)
                self.pendingRecoveryRefreshes.removeAll()
                guard !self.daemon.recoverySuspended else { return }
                await self.search.refresh()
                for refresh in pending {
                    await refresh()
                }
            }
        case .failed(.timeout):
            daemon.markUnresponsive()
        default: break
        }
    }
}
