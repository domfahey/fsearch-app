import AppKit
import SwiftUI
import os

/// First-launch entry point. A SwiftUI `Window` scene can't open itself at
/// launch on macOS 14, so the onboarding window is hosted directly.
@MainActor
enum OnboardingLauncher {
    /// What launch does about the helper.
    enum Decision: Equatable {
        /// First run: onboarding starts the helper at its helper step.
        case showOnboarding
        /// Onboarded already, or test mode: start the helper now.
        case startDaemon
    }

    /// The onboarding window while it is open.
    private(set) static var window: NSWindow?
    /// Watches the window so closing it can still start the helper.
    private static var closeObserver: NSObjectProtocol?
    /// Set once the helper has been started, by onboarding or on close.
    private(set) static var startedDaemon = false
    /// Where "onboarded" is read; a throwaway suite under test.
    static var defaults: UserDefaults = AppDefaults.store

    private static var onboarded: Bool { defaults.bool(forKey: "onboarded") }

    /// Test mode (UI tests) never shows onboarding: it would take focus from the panel.
    static func decision(onboarded: Bool, testMode: Bool) -> Decision {
        onboarded || testMode ? .startDaemon : .showOnboarding
    }

    /// Opens onboarding the first time; afterwards just starts the helper.
    static func launch(app: AppState) {
        let d = decision(onboarded: onboarded, testMode: app.options.testMode)
        Log.onboarding.info("launch: \(String(describing: d), privacy: .public)")
        switch d {
        case .startDaemon: startDaemon(app: app)
        case .showOnboarding: show(app: app)
        }
    }

    /// "Finish Setup…" in the menu: bring the window back while not onboarded.
    static func reopen(app: AppState) {
        guard !onboarded else { return }
        show(app: app)
    }

    /// Starts the helper outside any view, so closing a window doesn't cancel it.
    @discardableResult
    static func startDaemon(app: AppState) -> Task<Void, Never> {
        startedDaemon = true
        return Task { await app.daemon.start() }
    }

    /// Onboarding's own step 2 started the helper.
    static func noteDaemonStarted() { startedDaemon = true }

    /// Closes the onboarding window if it is open.
    static func close() { window?.close() }

    /// Forgets a closed window's run, so a test can start over.
    static func reset() {
        close()
        startedDaemon = false
    }

    private static func show(app: AppState) {
        if let window {
            AppActivation.activate()
            Presentation.present(window)
            return
        }
        let flow = OnboardingFlow(app: app, defaults: defaults)
        let w = HostSafeWindow(contentViewController: NSHostingController(rootView: OnboardingView(flow: flow).environmentObject(app)))
        w.title = "Welcome to FSearch"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { didClose(app: app) }
        }
        window = w
        AppActivation.activate()
        // The unit-test host orders it in invisibly and never key.
        Presentation.present(w)
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
    @AppStorage("onboarded", store: AppDefaults.store) private var onboarded = false

    var body: some View {
        if !onboarded { Button("Finish Setup…") { OnboardingLauncher.reopen(app: app) } }
    }
}
