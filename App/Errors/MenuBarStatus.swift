import Combine
import FSearchKit
import Foundation
import Observation
import SwiftUI

/// Turns the daemon's state (plus "skipped Full Disk Access") into a menu-bar warning.
/// `@Observable` so the scene body re-reads the icon when the warning changes.
@MainActor @Observable
final class MenuBarStatus {
    static let shared = MenuBarStatus()
    private(set) var warning: MenuBarWarning?
    @ObservationIgnored private var bound = false
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []

    /// The menu-bar symbol; the first call also starts following `app.daemon`.
    func icon(for app: AppState) -> String {
        bind(to: app.daemon)
        return warning?.symbol ?? "magnifyingglass"
    }

    private func bind(to daemon: DaemonManager) {
        guard !bound else { return }
        bound = true
        let skipped = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in () }.prepend(())
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
                let next = MenuBarWarning.evaluate(condition, skippedFullDiskAccess: UserDefaults.standard.bool(forKey: "skippedFullDiskAccess"))
                if next != self?.warning { self?.warning = next }
            }
            .store(in: &cancellables)
    }
}

/// First items of the menu while something needs attention.
struct MenuBarFixItem: View {
    @ObservedObject var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let w = MenuBarStatus.shared.warning {
            Text(w.message)
            if w.offersFix {
                Button("Fix…") { NSApp.activate(); openWindow(id: "index") }
            }
            Divider()
        }
    }
}
