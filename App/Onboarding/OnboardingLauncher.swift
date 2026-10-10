import AppKit
import SwiftUI

/// First-launch entry point. A SwiftUI `Window` scene can't open itself at
/// launch on macOS 14, so the onboarding window is hosted directly.
@MainActor
enum OnboardingLauncher {
    private static var window: NSWindow?

    /// Opens onboarding the first time; afterwards just starts the helper.
    static func launch(app: AppState) {
        guard !UserDefaults.standard.bool(forKey: "onboarded") else {
            Task { await app.daemon.start() }
            return
        }
        let w = NSWindow(contentViewController: NSHostingController(rootView: OnboardingView().environmentObject(app)))
        w.title = "Welcome to FSearch"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        // Dropping the content view stops the view's status polling.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { window?.contentViewController = nil; window = nil }
        }
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    static func close() { window?.close() }
}
