import AppKit
import FSearchKit
import SwiftUI
import os

/// The app: a menu-bar extra, a Settings scene and two debug windows. The floating panel is AppKit, installed by `PanelController`.
@main
struct FSearchApp: App {
    /// Receives `fsearch://` URL events from LaunchServices even when no SwiftUI window is open.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Shared by every scene.
    @StateObject private var app: AppState

    init() {
        LaunchOptions.current.configureHost()
        // A second copy would register a second helper and hotkey: hand over and quit.
        if LaunchGuards.anotherCopyIsRunning(options: .current) { exit(0) }
        let state = AppState.live()
        _app = StateObject(wrappedValue: state)
        // Hosting unit tests: start nothing (no helper, hotkey, onboarding or Sparkle).
        guard !state.options.unitTestHost else { return }
        let delegate = appDelegate
        DispatchQueue.main.async { LaunchGuards.startApp(state: state, delegate: delegate) }
    }

    /// No menu-bar item while hosting unit tests; UI tests (test mode) click it, so it stays there.
    static func showsMenuBarItem(_ options: LaunchOptions) -> Bool { !options.unitTestHost }

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(Self.showsMenuBarItem(app.options))) {
            MenuBarFixItem(app: app)
            MenuContent(app: app)
        } label: {
            MenuBarLabel(app: app)
        }
        Settings { SettingsView().environmentObject(app) }
        Window("Index Details", id: "index") { IndexDetailsView().environmentObject(app) }
            .handlesExternalEvents(matching: [])
        Window("Search Log", id: "log") { SearchLogView().environmentObject(app) }
            .handlesExternalEvents(matching: [])
    }
}

/// AppKit delegate: receives `fsearch://` URLs from LaunchServices, even when no SwiftUI window is open.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var openSearch: ((SearchURL) -> Void)?
    private var pending: SearchURL?

    /// Connects incoming URLs to the panel and replays any URL that arrived during cold launch.
    func connect(panel: PanelHost, app: AppState) {
        openSearch = { panel.show(app: app, search: $0) }
        if let search = pending {
            pending = nil
            panel.show(app: app, search: search)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let search = urls.compactMap(SearchURL.parse).last else { return }
        if let openSearch {
            openSearch(search)
        } else {
            pending = search
        }
    }
}

/// The menu's content lives in its own View so it can read `openWindow`.
struct MenuContent: View {
    @ObservedObject var app: AppState
    @Environment(\.openWindow) private var envOpenWindow
    @Environment(\.openSettings) private var envOpenSettings
    #if DEBUG
        private let openWindowOverride: ((String) -> Void)?
        private let openSettingsOverride: (() -> Void)?

        init(app: AppState, openWindow: ((String) -> Void)? = nil, openSettings: (() -> Void)? = nil) {
            self.app = app
            self.openWindowOverride = openWindow
            self.openSettingsOverride = openSettings
        }
    #endif

    private func openWindow(_ id: String) {
        #if DEBUG
            let open: (String) -> Void = openWindowOverride ?? { envOpenWindow(id: $0) }
        #else
            let open: (String) -> Void = { envOpenWindow(id: $0) }
        #endif
        MenuWindows.open(id, open)
    }

    private func openSettings() {
        #if DEBUG
            let open: () -> Void = openSettingsOverride ?? { envOpenSettings() }
        #else
            let open: () -> Void = { envOpenSettings() }
        #endif
        MenuWindows.openSettings(open)
    }

    var body: some View {
        Button("Search…") { PanelController.shared.toggle(app: app) }
        Divider()
        if app.debugMode {
            Button("Index Details…") { openWindow("index") }
            Button("Search Log…") { openWindow("log") }
            Divider()
        }
        DebugMenuItem(app: app)
        FinishSetupMenuItem(app: app)
        Menu("Help") { HelpMenuContent(app: app) }
        Button("About FSearch") { AppMenuActions.showAbout() }
        // Not SettingsLink: it doesn't bring a menu-bar app to the front.
        Button("Settings…") { openSettings() }
        CheckForUpdatesItem()
        Button("Quit FSearch") { AppMenuActions.quit() }
    }
}

/// Items inside the menu bar's Help submenu, extracted so view tests can press each action directly.
struct HelpMenuContent: View {
    @ObservedObject var app: AppState

    var body: some View {
        ForEach(HelpLinks.items, id: \.title) { item in
            Button(item.title) { FileActions.workspace.open(item.url) }
        }
        Divider()
        ForEach(HelpLinks.community, id: \.title) { item in
            Button(item.title) { FileActions.workspace.open(item.url) }
        }
        Divider()
        Button(HelpLinks.reportTitle) { HelpLinks.reportIssue(daemon: app.daemon, workspace: FileActions.workspace) }
    }
}

/// Opening a window from the menu. An LSUIElement app isn't active, so
/// without activating first the window opens behind the frontmost app.
@MainActor
enum MenuWindows {
    static func open(_ id: String, _ openWindow: (String) -> Void) {
        AppActivation.activate()
        openWindow(id)
    }

    static func openSettings(_ open: () -> Void) {
        AppActivation.activate()
        open()
    }
}

/// Checks at launch, outside test mode, before anything starts.
@MainActor
enum LaunchGuards {
    /// Posted when a second copy of FSearch launches so the running LSUIElement instance opens the search panel.
    static let reopenNotification = Notification.Name("com.domfahey.fsearch.reopen")

    /// Starts the app's runtime services, or offers to move into Applications if launched from a bad location.
    static func startApp(
        state: AppState, delegate: AppDelegate,
        panel: PanelController = .shared,
        bundleURL: URL = Bundle.main.bundleURL,
        activationCenter: NotificationCenter = .default,
        reopenCenter: NotificationCenter = DistributedNotificationCenter.default(),
        offerMove: ((InstallLocation.Problem) -> Void)? = nil
    ) {
        // Run from a download's temporary copy or the DMG: never register
        // the helper from there; offer the move to Applications, then quit.
        if let problem = installProblem(options: state.options, bundleURL: bundleURL) {
            if let offerMove { offerMove(problem) } else { self.offerMove(problem) }
            return
        }
        Updater.start()
        panel.install(app: state)
        OnboardingLauncher.launch(app: state)
        observeActivation(daemon: state.daemon, center: activationCenter)
        observeReopen(panel: panel, app: state, center: reopenCenter)
        delegate.connect(panel: panel, app: state)
    }

    /// Another FSearch is running: ask it to open the panel, bring it forward, and let the caller quit.
    static func anotherCopyIsRunning(
        options: LaunchOptions, center: NotificationCenter = DistributedNotificationCenter.default(),
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        runningApps: ((String) -> [(pid: pid_t, activate: () -> Void)])? = nil,
        me: pid_t = getpid()
    ) -> Bool {
        guard !options.testMode, let id = bundleIdentifier else { return false }
        let running =
            runningApps?(id)
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: id).map { app in
                (app.processIdentifier, { _ = app.activate() })
            }
        guard let pid = SingleInstance.other(pids: running.map(\.pid), me: me) else { return false }
        Log.daemon.info("another FSearch is running (pid \(pid, privacy: .public)): quitting")
        notifyOtherInstance(center: center)
        running.first { $0.pid == pid }?.activate()
        return true
    }

    /// Tells the running instance to show the search panel.
    static func notifyOtherInstance(center: NotificationCenter = DistributedNotificationCenter.default()) {
        center.post(name: reopenNotification, object: nil)
    }

    private static var reopenObserver: NSObjectProtocol?
    /// Opens the search panel when another launch of FSearch.app hands over to this running instance.
    static func observeReopen(
        panel: PanelHost = PanelController.shared, app: AppState,
        center: NotificationCenter = DistributedNotificationCenter.default()
    ) {
        guard reopenObserver == nil else { return }
        reopenObserver = center.addObserver(forName: reopenNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                if !panel.isVisible { panel.showExternally(app: app) }
            }
        }
    }

    #if DEBUG
        static func stopObservingReopen(center: NotificationCenter) {
            if let o = reopenObserver { center.removeObserver(o) }
            reopenObserver = nil
        }
    #endif

    static func installProblem(options: LaunchOptions, bundleURL: URL = Bundle.main.bundleURL) -> InstallLocation.Problem? {
        guard !options.testMode else { return nil }
        let readOnly = (try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? false
        return InstallLocation.problem(
            bundlePath: bundleURL.path, translocated: InstallMover.isTranslocated(bundleURL), readOnlyVolume: readOnly)
    }

    static func offerMove(
        _ problem: InstallLocation.Problem,
        runAlert: ((NSAlert) -> NSApplication.ModalResponse)? = nil,
        move: ((URL) -> Void)? = nil,
        terminate: (() -> Void)? = nil
    ) {
        Log.daemon.info("launched from a bad location: \(String(describing: problem), privacy: .public)")
        AppActivation.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "Move FSearch to Applications")
        alert.informativeText = problem.message
        alert.addButton(withTitle: String(localized: "Move to Applications"))
        alert.addButton(withTitle: String(localized: "Quit"))
        let response = runAlert?(alert) ?? alert.runModal()
        if response == .alertFirstButtonReturn {
            if let move { move(Bundle.main.bundleURL) } else { InstallMover.moveToApplications(from: Bundle.main.bundleURL) }
        }
        if let terminate { terminate() } else { NSApp.terminate(nil) }
    }

    /// Back from System Settings after the menu's Full Disk Access item.
    /// Observes once; tests pass their own notification center.
    private static var activationObserver: NSObjectProtocol?
    static func observeActivation(daemon: DaemonManager, center: NotificationCenter = .default) {
        guard activationObserver == nil else { return }
        activationObserver = center.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { _ = Task { await daemon.appBecameActive() } }
        }
    }

    #if DEBUG
        /// Tests stop the observer they started, so the next test can observe again.
        static func stopObservingActivation(center: NotificationCenter) {
            if let o = activationObserver { center.removeObserver(o) }
            activationObserver = nil
        }
    #endif
}
