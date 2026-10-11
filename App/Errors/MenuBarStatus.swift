import Combine
import FSearchKit
import Foundation
import Observation
import SwiftUI

/// Turns the daemon's state (plus "skipped Full Disk Access") into a menu-bar warning.
/// `@Observable` so `MenuBarLabel` redraws the icon when the warning changes.
/// Also holds the per-outage restart budget, shared by every panel open.
@MainActor @Observable
final class MenuBarStatus {
    static let shared = MenuBarStatus()
    /// The current warning, or nil when all is well.
    private(set) var warning: MenuBarWarning?
    /// Restarts left in the current daemon outage; refilled when results arrive.
    @ObservationIgnored var restartBudget = RestartBudget()
    /// Rate-limits re-checking a daemon marked down while searches succeed.
    @ObservationIgnored var recoveryCheck = RecoveryCheck()
    @ObservationIgnored private var bound = false
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    /// Where "skipped" and "don't remind me" are read; a throwaway suite under test.
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = AppDefaults.store) { self.defaults = defaults }

    /// The menu-bar symbol; the first call also starts following `app.daemon`.
    func icon(for app: AppState) -> String {
        bind(to: app.daemon)
        // A waiting update shows quietly as a badge on the icon; warnings take priority.
        return warning?.symbol ?? (UpdateReminderModel.shared.indicatorVisible ? "arrow.down.circle" : "magnifyingglass")
    }

    /// Follows the daemon's state and the defaults (the skipped and dismissed flags) to keep ``warning`` current.
    private func bind(to daemon: DaemonManager) {
        guard !bound else { return }
        bound = true
        // Defaults can change on any thread: hop to main before anything else
        // runs, and keep the map nonisolated so an off-main post can't trap.
        let skipped = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .map { @Sendable _ in () }
            .prepend(())
        let defaults = defaults
        Publishers.CombineLatest(daemon.$state, skipped)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, _ in
                let next = MenuBarWarning.evaluate(
                    MenuBarStatus.condition(state), skippedFullDiskAccess: defaults.bool(forKey: "skippedFullDiskAccess"),
                    dismissedReminder: defaults.bool(forKey: FullDiskAccessReminder.dismissedKey))
                if next != self?.warning { self?.warning = next }
            }
            .store(in: &cancellables)
    }

    /// The daemon's state as the menu bar sees it.
    nonisolated static func condition(_ state: DaemonManager.State) -> DaemonCondition {
        switch state {
        case .checking: .checking
        case let .running(s): .running(fullDiskAccess: s.fullDiskAccess)
        case .indexing: .indexing
        case .needsApproval: .needsApproval
        case .failed(DaemonManager.unresponsiveMessage): .unresponsive
        case .failed: .failed
        }
    }
}

/// The reminder's actions, apart from the view so tests can run them.
@MainActor
enum FullDiskAccessReminder {
    /// Privacy settings' Full Disk Access list.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    /// The defaults key for "Don't Remind Me".
    static let dismissedKey = "dismissedFullDiskAccessReminder"

    /// Opens the Full Disk Access list.
    static func openSettings() { FileActions.workspace.open(settingsURL) }

    /// The menu's Full Disk Access item. For our own helper, a grant only
    /// takes effect after a restart, so arm one for when the app is active again.
    static func turnOn(daemon: DaemonManager) {
        if daemon.ownsDaemon { daemon.armFullDiskAccessRestart() }
        openSettings()
    }

    /// Stores the flag; the defaults-change notification re-evaluates the menu bar.
    static func dismiss(defaults: UserDefaults = AppDefaults.store) { defaults.set(true, forKey: dismissedKey) }
}

/// The menu-bar icon. A View, so Observation tracks `warning` reliably.
struct MenuBarLabel: View {
    let app: AppState

    var body: some View {
        Image(systemName: MenuBarStatus.shared.icon(for: app))
            .accessibilityLabel("FSearch")
    }
}

/// First items of the menu while something needs attention.
struct MenuBarFixItem: View {
    @ObservedObject var app: AppState
    /// Where the warning comes from; tests pass their own.
    let status: MenuBarStatus
    @Environment(\.openWindow) private var openWindow

    init(app: AppState, status: MenuBarStatus = .shared) {
        self.app = app
        self.status = status
    }

    var body: some View {
        UpdateAvailableItem()
        if let w = status.warning {
            Text(w.message)
            if w.offersFix {
                Button("Fix…") {
                    AppActivation.activate(); openWindow(id: "index")
                }
            }
            if w.offersFullDiskAccess {
                Button(MenuBarWarning.fullDiskAccessItemTitle(ownsDaemon: app.daemon.ownsDaemon)) {
                    FullDiskAccessReminder.turnOn(daemon: app.daemon)
                }
                Button("Don't Remind Me") { FullDiskAccessReminder.dismiss() }
            }
            Divider()
        }
    }
}
