/// Decides when a scheduled update shows as a quiet menu-bar indicator instead of
/// Sparkle's window (gentle reminders for a menu-bar app that is never frontmost).
public struct UpdateReminder: Equatable, Sendable {
    public private(set) var indicatorVisible = false

    public init() {}

    /// At launch, a reminder left from the previous run asks Sparkle to look
    /// again in the background, which brings the indicator back if the update
    /// is still there.
    public static func checkAtLaunch(persistedVisible: Bool, updaterRunning: Bool) -> Bool {
        persistedVisible && updaterRunning
    }

    /// Let Sparkle pop its window for a scheduled update only when the app is
    /// already in focus; otherwise we show the indicator.
    public func sparkleShouldShowScheduled(immediateFocus: Bool) -> Bool { immediateFocus }

    /// An update is about to be presented. When Sparkle won't show it and the user
    /// didn't ask for it, remind quietly.
    public mutating func willShow(bySparkle: Bool, userInitiated: Bool) {
        indicatorVisible = !bySparkle && !userInitiated
    }

    /// The user looked at the update.
    public mutating func userDidReceiveAttention() { indicatorVisible = false }

    /// The update session ended (installed, skipped or dismissed).
    public mutating func sessionWillFinish() { indicatorVisible = false }
}
