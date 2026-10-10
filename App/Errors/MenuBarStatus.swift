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
    private(set) var warning: MenuBarWarning?
    /// Restarts left in the current daemon outage; refilled when results arrive.
    @ObservationIgnored var restartBudget = RestartBudget()
    /// Rate-limits re-checking a daemon marked down while searches succeed.
    @ObservationIgnored var recoveryCheck = RecoveryCheck()
    @ObservationIgnored private var bound = false
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []

    /// The menu-bar symbol; the first call also starts following `app.daemon`.
    func icon(for app: AppState) -> String {
        bind(to: app.daemon)
        // A waiting update shows quietly as a badge on the icon; warnings take priority.
        return warning?.symbol ?? (UpdateReminderModel.shared.indicatorVisible ? "arrow.down.circle" : "magnifyingglass")
    }

    private func bind(to daemon: DaemonManager) {
        guard !bound else { return }
        bound = true
        // Defaults can change on any thread: hop to main before anything else
        // runs, and keep the map nonisolated so an off-main post can't trap.
        let skipped = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .map { @Sendable _ in () }
            .prepend(())
        Publishers.CombineLatest(daemon.$state, skipped)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, _ in
                let condition: DaemonCondition = switch state {
                case .checking: .checking
                case let .running(s): .running(fullDiskAccess: s.fullDiskAccess)
                case .indexing: .indexing
                case .needsApproval: .needsApproval
                case .failed: .failed
                }
                let next = MenuBarWarning.evaluate(condition, skippedFullDiskAccess: UserDefaults.standard.bool(forKey: "skippedFullDiskAccess"),
                                                 dismissedReminder: UserDefaults.standard.bool(forKey: "dismissedFullDiskAccessReminder"))
                if next != self?.warning { self?.warning = next }
            }
            .store(in: &cancellables)
    }
}

/// The reminder's actions, apart from the view so tests can run them.
@MainActor
enum FullDiskAccessReminder {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
    static let dismissedKey = "dismissedFullDiskAccessReminder"

    static func openSettings() { FileActions.workspace.open(settingsURL) }

    /// Stores the flag; the defaults-change notification re-evaluates the menu bar.
    static func dismiss(defaults: UserDefaults = .standard) { defaults.set(true, forKey: dismissedKey) }
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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        UpdateAvailableItem()
        if let w = MenuBarStatus.shared.warning {
            Text(w.message)
            if w.offersFix {
                Button("Fix…") { NSApp.activate(); openWindow(id: "index") }
            }
            if w.offersFullDiskAccess {
                Button(MenuBarWarning.fullDiskAccessItemTitle(ownsDaemon: app.daemon.ownsDaemon)) {
                    FullDiskAccessReminder.openSettings()
                }
                Button("Don't Remind Me") { FullDiskAccessReminder.dismiss() }
            }
            Divider()
        }
    }
}
