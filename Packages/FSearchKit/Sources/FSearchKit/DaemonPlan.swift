/// Use a daemon that already answers (e.g. a CLI install's); otherwise run
/// the bundled one, so two never compete for the same data folder.
public enum DaemonPlan: Equatable, Sendable {
    case useExisting, registerBundled
    public static func decide(existingAnswers: Bool) -> DaemonPlan { existingAnswers ? .useExisting : .registerBundled }
}
