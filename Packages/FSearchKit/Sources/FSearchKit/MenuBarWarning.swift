/// The daemon's condition, reduced to what the menu bar cares about.
public enum DaemonCondition: Equatable, Sendable {
    case checking, running(fullDiskAccess: Bool), indexing, needsApproval, failed
}

/// A menu-bar warning: a "Fix…" problem, or a gentle reminder.
public struct MenuBarWarning: Equatable, Sendable {
    public let message: String
    /// True when the menu should offer "Fix…" (opens Index Details).
    public let offersFix: Bool
    public var symbol: String { "exclamationmark.magnifyingglass" }

    public static func evaluate(_ c: DaemonCondition, skippedFullDiskAccess: Bool) -> MenuBarWarning? {
        switch c {
        case .failed: MenuBarWarning(message: "The search helper isn't running", offersFix: true)
        case .needsApproval: MenuBarWarning(message: "The search helper needs your approval", offersFix: true)
        case let .running(fda) where !fda && !skippedFullDiskAccess:
            MenuBarWarning(message: "Full Disk Access is off, so some files won't be found", offersFix: false)
        case .checking, .indexing, .running: nil
        }
    }
}
