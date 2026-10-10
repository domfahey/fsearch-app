import AppKit
import SwiftUI

/// First-launch entry point. A SwiftUI `Window` scene can't open itself at
/// launch on macOS 14, so the onboarding window is hosted directly.
@MainActor
enum OnboardingLauncher {
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?
    /// Set once the helper has been started, by onboarding or on close.
    private static var startedDaemon = false

    private static var onboarded: Bool { UserDefaults.standard.bool(forKey: "onboarded") }

    /// Opens onboarding the first time; afterwards just starts the helper.
    static func launch(app: AppState) {
        // Test mode (UI tests) never shows onboarding: it would take focus from the panel.
        guard !onboarded, !AppState.testMode else { startDaemon(app: app); return }
        show(app: app)
    }

    /// "Finish Setup…" in the menu: bring the window back while not onboarded.
    static func reopen(app: AppState) {
        guard !onboarded else { return }
        show(app: app)
    }

    /// Starts the helper outside any view, so closing a window doesn't cancel it.
    static func startDaemon(app: AppState) {
        startedDaemon = true
        Task { await app.daemon.start() }
    }

    /// Onboarding's own step 2 started the helper.
    static func noteDaemonStarted() { startedDaemon = true }

    static func close() { window?.close() }

    private static func show(app: AppState) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView().environmentObject(app)))
        w.title = "Welcome to FSearch"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { didClose(app: app) }
        }
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private static func didClose(app: AppState) {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        // Dropping the content view stops the view's status polling.
        window?.contentViewController = nil
        window = nil
        // Closed before step 2: the app still needs its helper.
        if !startedDaemon { startDaemon(app: app) }
    }
}

/// The menu's "Finish Setup…" item, shown until onboarding is done.
struct FinishSetupMenuItem: View {
    let app: AppState
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        if !onboarded { Button("Finish Setup…") { OnboardingLauncher.reopen(app: app) } }
    }
}
