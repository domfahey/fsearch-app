import Foundation

/// What the app does at launch. It never stops or replaces a daemon it didn't
/// start: one that already answers (e.g. a CLI install's) is used, and so is a
/// CLI login agent that is only briefly down. Only when nothing else is around
/// does it register the bundled helper, and never again once it is enabled.
public enum DaemonPlan: Equatable, Sendable {
    /// Use whatever answers (or will answer soon): just refresh.
    case useExisting
    /// Our helper is already registered and enabled: just refresh.
    case refreshOwn
    /// Our helper waits for the user in Login Items: say so, don't register.
    case needsApproval
    /// Nothing answers yet: ping again for `recheckWindow`, then `afterRecheck`.
    case recheckThenRegister
    /// Register the bundled helper.
    case registerBundled

    /// `SMAppService.Status`, without importing ServiceManagement.
    public enum ServiceStatus: Equatable, Sendable, CaseIterable {
        case notRegistered, enabled, requiresApproval, notFound
    }

    /// How long to keep pinging before registering (a CLI daemon restarting).
    public static let recheckWindow: Duration = .seconds(3)

    public static func decide(existingAnswers: Bool, ownStatus: ServiceStatus, cliAgentInstalled: Bool) -> DaemonPlan {
        if existingAnswers { return .useExisting }
        if ownStatus == .enabled { return .refreshOwn }
        // Before approval: a CLI agent's daemon, even one restarting, is
        // preferred to asking the user to approve a second daemon.
        if cliAgentInstalled { return .useExisting }
        if ownStatus == .requiresApproval { return .needsApproval }
        return .recheckThenRegister
    }

    /// After the bounded re-ping of `.recheckThenRegister`.
    public static func afterRecheck(existingAnswers: Bool) -> DaemonPlan {
        existingAnswers ? .useExisting : .registerBundled
    }

    /// After a successful `register()`.
    public static func afterRegister(ownStatus: ServiceStatus) -> DaemonPlan {
        ownStatus == .requiresApproval ? .needsApproval : .refreshOwn
    }
}

public extension DaemonPlan {
    enum RestartAction: Equatable, Sendable { case refreshOnly, reregister }
    /// The app only restarts a daemon it registered itself; any other
    /// (a CLI install's, a test daemon) is left running.
    static func restartAction(owns: Bool) -> RestartAction { owns ? .reregister : .refreshOnly }

    enum NoAnswer: Equatable, Sendable { case needsApproval, failed }
    /// The daemon didn't answer a refresh. A helper waiting for approval
    /// isn't a failure until it is enabled. `ownStatus` is nil in test mode.
    static func noAnswer(wasNeedingApproval: Bool, ownStatus: ServiceStatus?) -> NoAnswer {
        switch ownStatus {
        case nil, .enabled?: .failed
        case .requiresApproval?: .needsApproval
        default: wasNeedingApproval ? .needsApproval : .failed
        }
    }
}

/// Re-checks a daemon the app thinks is down (or waiting for approval) when
/// searches succeed anyway, at most once per `interval`.
public struct RecoveryCheck: Equatable, Sendable {
    public let interval: TimeInterval
    private var last: Date?

    public init(interval: TimeInterval = 5) { self.interval = interval }

    public mutating func shouldRefresh(daemonUnhealthy: Bool, now: Date = Date()) -> Bool {
        guard daemonUnhealthy else { return false }
        if let last, now.timeIntervalSince(last) < interval { return false }
        last = now
        return true
    }
}
