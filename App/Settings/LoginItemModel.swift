import FSearchKit
import Foundation

/// "Open FSearch at login": the real status of the app's own login item, and
/// the last failure to change it (shown inline, never as an alert).
@MainActor
final class LoginItemModel: ObservableObject {
    /// What the toggle shows.
    enum Display: Equatable {
        /// No login item (test mode).
        case unavailable
        /// Not registered.
        case off
        /// Registered and enabled.
        case on
        /// Registered, waiting for approval in Login Items.
        case needsApproval
    }

    /// The login item's state.
    @Published private(set) var display: Display = .off
    /// The last failure to change the item, shown inline.
    @Published private(set) var error: String?
    private let service: LoginItemService?

    /// nil service (test mode): the toggle is shown but disabled.
    init(service: LoginItemService?) {
        self.service = service
        refresh()
    }

    /// Re-reads the status, e.g. after the user came back from System Settings.
    func refresh() {
        guard let service else { display = .unavailable; return }
        switch service.status {
        case .enabled: display = .on
        case .requiresApproval: display = .needsApproval
        case .notRegistered, .notFound: display = .off
        }
    }

    /// The toggle shows on while registered, even before approval.
    var isOn: Bool { display == .on || display == .needsApproval }

    /// The line under the toggle.
    var statusText: String {
        switch display {
        case .unavailable: "Not available in this build."
        case .off: "FSearch won't open when you log in."
        case .on: "FSearch opens when you log in."
        case .needsApproval: "Waiting for your approval in Login Items."
        }
    }

    /// Registers or unregisters the item, then re-reads its status.
    func set(_ on: Bool) async {
        guard let service else { return }
        error = nil
        do {
            if on { try service.register() } else { try await service.unregister() }
        } catch {
            // Registering can fail yet leave "requires approval"; the status says which.
            if !(on && service.status == .requiresApproval) {
                self.error = "Couldn't \(on ? "turn on" : "turn off") Open at login: \(error.localizedDescription)"
            }
        }
        refresh()
    }

    /// Opens System Settings at Login Items.
    func openLoginItems() { service?.openSystemSettingsLoginItems() }
}
