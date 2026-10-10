/// Use a daemon that already answers (e.g. a CLI install's); otherwise run
/// the bundled one, so two never compete for the same data folder.
public enum DaemonPlan: Equatable, Sendable {
    case useExisting, registerBundled
    public static func decide(existingAnswers: Bool) -> DaemonPlan { existingAnswers ? .useExisting : .registerBundled }
}

public extension DaemonPlan {
    enum RestartAction: Equatable, Sendable { case refreshOnly, reregister }
    /// The app only restarts a daemon it registered itself; any other
    /// (a CLI install's, a test daemon) is left running.
    static func restartAction(owns: Bool) -> RestartAction { owns ? .reregister : .refreshOnly }
}
