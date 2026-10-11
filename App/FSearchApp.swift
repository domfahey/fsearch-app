import AppKit
import FSearchKit
import SwiftUI
import os

/// The app: a menu-bar extra, a Settings scene and two debug windows. The floating panel is AppKit, installed by `PanelController`.
@main
struct FSearchApp: App {
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
        DispatchQueue.main.async {
            // Run from a download's temporary copy or the DMG: never register
            // the helper from there; offer the move to Applications, then quit.
            if let problem = LaunchGuards.installProblem(options: state.options) {
                LaunchGuards.offerMove(problem)
                return
            }
            Updater.start()
            PanelController.shared.install(app: state)
            OnboardingLauncher.launch(app: state)
            LaunchGuards.observeActivation(daemon: state.daemon)
        }
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
        Window("Search Log", id: "log") { SearchLogView().environmentObject(app) }
    }
}

/// The menu's content lives in its own View so it can read `openWindow`.
struct MenuContent: View {
    @ObservedObject var app: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Search…") { PanelController.shared.toggle(app: app) }
        Divider()
        if app.debugMode {
            Button("Index Details…") { MenuWindows.open("index") { openWindow(id: $0) } }
            Button("Search Log…") { MenuWindows.open("log") { openWindow(id: $0) } }
            Divider()
        }
        DebugMenuItem(app: app)
        FinishSetupMenuItem(app: app)
        Menu("Help") {
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
        Button("About FSearch") {
            AppActivation.activate(); NSApp.orderFrontStandardAboutPanel(nil)
        }
        // Not SettingsLink: it doesn't bring a menu-bar app to the front.
        Button("Settings…") { MenuWindows.openSettings { openSettings() } }
        CheckForUpdatesItem()
        Button("Quit FSearch") { NSApp.terminate(nil) }
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
    /// Another FSearch is running: bring it forward. The caller quits.
    static func anotherCopyIsRunning(options: LaunchOptions) -> Bool {
        guard !options.testMode, let id = Bundle.main.bundleIdentifier else { return false }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: id)
        guard let pid = SingleInstance.other(pids: running.map(\.processIdentifier), me: getpid()) else { return false }
        Log.daemon.info("another FSearch is running (pid \(pid, privacy: .public)): quitting")
        running.first { $0.processIdentifier == pid }?.activate()
        return true
    }

    static func installProblem(options: LaunchOptions, bundleURL: URL = Bundle.main.bundleURL) -> InstallLocation.Problem? {
        guard !options.testMode else { return nil }
        let readOnly = (try? bundleURL.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly) ?? false
        return InstallLocation.problem(
            bundlePath: bundleURL.path, translocated: InstallMover.isTranslocated(bundleURL), readOnlyVolume: readOnly)
    }

    static func offerMove(_ problem: InstallLocation.Problem) {
        Log.daemon.info("launched from a bad location: \(String(describing: problem), privacy: .public)")
        AppActivation.activate()
        let alert = NSAlert()
        alert.messageText = "Move FSearch to Applications"
        alert.informativeText = problem.message
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertFirstButtonReturn {
            InstallMover.moveToApplications(from: Bundle.main.bundleURL)
        }
        NSApp.terminate(nil)
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
