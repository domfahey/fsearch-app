/// The daemon's condition, reduced to what the menu bar cares about.
public enum DaemonCondition: Equatable, Sendable {
    case checking, running(fullDiskAccess: Bool), indexing, needsApproval, failed
}

/// A menu-bar warning: a "Fix…" problem, or a gentle reminder.
public struct MenuBarWarning: Equatable, Sendable {
    public let message: String
    /// True when the menu should offer "Fix…" (opens Index Details).
    public let offersFix: Bool
    /// True for the reminder after "Skip for now": the menu offers a Full Disk
    /// Access item and "Don't Remind Me", and the icon is the subtler variant.
    public let offersFullDiskAccess: Bool
    public var symbol: String { offersFullDiskAccess ? "magnifyingglass.circle" : "exclamationmark.magnifyingglass" }

    public init(message: String, offersFix: Bool, offersFullDiskAccess: Bool = false) {
        self.message = message
        self.offersFix = offersFix
        self.offersFullDiskAccess = offersFullDiskAccess
    }

    /// The menu item that opens Privacy & Security → Full Disk Access. A CLI
    /// daemon is a different binary, so the item says whose grant it is.
    public static func fullDiskAccessItemTitle(ownsDaemon: Bool) -> String {
        ownsDaemon ? "Turn On Full Disk Access…" : "Grant Full Disk Access to fsearch…"
    }

    public static func evaluate(_ c: DaemonCondition, skippedFullDiskAccess: Bool,
                                dismissedReminder: Bool = false) -> MenuBarWarning? {
        switch c {
        case .failed: MenuBarWarning(message: "The search helper isn't running", offersFix: true)
        case .needsApproval: MenuBarWarning(message: "The search helper needs your approval", offersFix: true)
        case let .running(fda) where !fda && !skippedFullDiskAccess:
            MenuBarWarning(message: "Full Disk Access is off, so some files won't be found", offersFix: false)
        case let .running(fda) where !fda && !dismissedReminder:
            MenuBarWarning(message: "Full Disk Access is off, so some files won't be found", offersFix: false, offersFullDiskAccess: true)
        case .checking, .indexing, .running: nil
        }
    }
}
