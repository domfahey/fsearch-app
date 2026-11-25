/// The daemon's condition, reduced to what the menu bar cares about.
public enum DaemonCondition: Equatable, Sendable {
    /// Asking the daemon; nothing to warn about yet.
    case checking
    /// Answering; `fullDiskAccess` is whether it can read protected folders.
    case running(fullDiskAccess: Bool)
    /// Building the first index.
    case indexing
    /// The bundled helper waits for approval in Login Items.
    case needsApproval
    /// Not running: nothing answers, or the helper failed to start.
    case failed
    /// There but not answering searches (timeouts, or the restarts ran out).
    case unresponsive
}

/// A menu-bar warning: a "Fix…" problem, or a gentle reminder.
public struct MenuBarWarning: Equatable, Sendable {
    /// The text shown in the menu.
    public let message: String
    /// True when the menu should offer "Fix…" (opens Index Details).
    public let offersFix: Bool
    /// True when the menu should offer the Full Disk Access item.
    public let offersFullDiskAccess: Bool
    /// True for the quieter reminder after "Skip for now": offers "Don't Remind Me"
    /// and uses the subtler menu-bar icon.
    public let offersDismiss: Bool
    /// The menu bar icon: the subtler variant for the dismissible skipped-onboarding reminder.
    public var symbol: String { offersDismiss ? "magnifyingglass.circle" : "exclamationmark.magnifyingglass" }

    /// Creates a warning.
    public init(message: String, offersFix: Bool, offersFullDiskAccess: Bool = false, offersDismiss: Bool = false) {
        self.message = message
        self.offersFix = offersFix
        self.offersFullDiskAccess = offersFullDiskAccess
        self.offersDismiss = offersDismiss
    }

    /// The menu item that opens Privacy & Security → Full Disk Access. A CLI
    /// daemon is a different binary, so the item says whose grant it is.
    public static func fullDiskAccessItemTitle(ownsDaemon: Bool) -> String {
        // Full Disk Access is granted per binary; a CLI daemon is not the app's helper.
        ownsDaemon ? "Turn On Full Disk Access…" : "Grant Full Disk Access to fsearch…"
    }

    /// The warning to show for a daemon condition, or nil for none.
    ///
    /// Missing Full Disk Access keeps the prominent icon and offers the Full Disk Access
    /// item (without "Don't Remind Me") when permission was never skipped; after "Skip for now"
    /// it becomes the quieter, dismissible reminder.
    ///
    /// - Parameters:
    ///   - c: The daemon's condition.
    ///   - skippedFullDiskAccess: Whether the user skipped Full Disk Access in onboarding.
    ///   - dismissedReminder: Whether the user chose "Don't Remind Me".
    public static func evaluate(
        _ c: DaemonCondition, skippedFullDiskAccess: Bool,
        dismissedReminder: Bool = false
    ) -> MenuBarWarning? {
        switch c {
        case .failed: MenuBarWarning(message: "The search helper isn't running", offersFix: true)
        case .unresponsive: MenuBarWarning(message: "The search helper isn't answering", offersFix: true)
        case .needsApproval: MenuBarWarning(message: "The search helper needs your approval", offersFix: true)
        case let .running(fda) where !fda && !skippedFullDiskAccess:
            MenuBarWarning(
                message: "Full Disk Access is off, so some files won't be found", offersFix: false, offersFullDiskAccess: true,
                offersDismiss: false)
        case let .running(fda) where !fda && !dismissedReminder:
            MenuBarWarning(
                message: "Full Disk Access is off, so some files won't be found", offersFix: false, offersFullDiskAccess: true,
                offersDismiss: true)
        case .checking, .indexing, .running: nil
        }
    }
}
