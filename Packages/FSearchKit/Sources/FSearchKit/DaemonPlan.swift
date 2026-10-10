import Foundation

/// What the app does at launch about the search daemon.
///
/// The invariant: the app never takes over. It never stops or replaces a daemon it didn't
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

    /// `SMAppService.Status`, without importing ServiceManagement so the logic stays testable.
    public enum ServiceStatus: Equatable, Sendable, CaseIterable {
        /// Not registered yet.
        case notRegistered
        /// Registered and allowed to run.
        case enabled
        /// Registered, but the user must approve it in Login Items.
        case requiresApproval
        /// The helper isn't in the app bundle.
        case notFound
    }

    /// How long to keep pinging before registering (a CLI daemon restarting).
    public static let recheckWindow: Duration = .seconds(3)

    /// Chooses the launch plan.
    ///
    /// - Parameters:
    ///   - existingAnswers: Whether a daemon already answers a ping.
    ///   - ownStatus: The state of the helper bundled with the app.
    ///   - cliAgentInstalled: Whether a CLI login agent (`fsearch install --login`) exists, even if its daemon is briefly down.
    /// - Returns: ``useExisting`` whenever something answers or a CLI agent is installed, even if our helper needs approval, so the user is never asked to approve a second daemon.
    public static func decide(existingAnswers: Bool, ownStatus: ServiceStatus, cliAgentInstalled: Bool) -> DaemonPlan {
        if existingAnswers { return .useExisting }
        if ownStatus == .enabled { return .refreshOwn }
        // Before approval: a CLI agent's daemon, even one restarting, is
        // preferred to asking the user to approve a second daemon.
        if cliAgentInstalled { return .useExisting }
        if ownStatus == .requiresApproval { return .needsApproval }
        return .recheckThenRegister
    }

    /// The plan after the bounded re-ping of `.recheckThenRegister`.
    ///
    /// - Parameter existingAnswers: Whether a daemon answered during the recheck window.
    public static func afterRecheck(existingAnswers: Bool) -> DaemonPlan {
        existingAnswers ? .useExisting : .registerBundled
    }

    /// The plan after a successful `register()`.
    ///
    /// - Parameter ownStatus: The helper's status once registered; macOS may still need the user's approval.
    public static func afterRegister(ownStatus: ServiceStatus) -> DaemonPlan {
        ownStatus == .requiresApproval ? .needsApproval : .refreshOwn
    }
}

/// Restart and no-answer decisions for a daemon the app is already managing.
public extension DaemonPlan {
    /// What a restart request does: just refresh, or re-register the helper.
    enum RestartAction: Equatable, Sendable {
        /// Leave the daemon running and re-read its state.
        case refreshOnly
        /// Unregister and register the app's own helper again.
        case reregister
    }
    /// The app only restarts a daemon it registered itself; any other
    /// (a CLI install's, a test daemon) is left running.
    ///
    /// - Parameter owns: Whether the app registered the running helper.
    static func restartAction(owns: Bool) -> RestartAction { owns ? .reregister : .refreshOnly }

    /// How an unanswered refresh is reported.
    enum NoAnswer: Equatable, Sendable {
        /// The helper is waiting for the user's approval.
        case needsApproval
        /// The daemon is down.
        case failed
    }
    /// The daemon didn't answer a refresh. A helper waiting for approval
    /// isn't a failure until it is enabled. `ownStatus` is nil in test mode.
    ///
    /// - Parameters:
    ///   - wasNeedingApproval: Whether the helper was already waiting for approval.
    ///   - ownStatus: The helper's current status, or nil when there is no helper (test mode).
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
///
/// The throttle keeps a burst of successful searches from firing a status request each.
public struct RecoveryCheck: Equatable, Sendable {
    /// Minimum seconds between two refreshes.
    public let interval: TimeInterval
    private var last: Date?

    /// Creates a check that has not fired yet.
    ///
    /// - Parameter interval: Minimum seconds between refreshes.
    public init(interval: TimeInterval = 5) { self.interval = interval }

    /// Whether to refresh the daemon's state now; true records the time, so the next call within `interval` is false.
    ///
    /// - Parameters:
    ///   - daemonUnhealthy: Whether the app currently shows the daemon as down or awaiting approval.
    ///   - now: The current time (injectable for tests).
    public mutating func shouldRefresh(daemonUnhealthy: Bool, now: Date = Date()) -> Bool {
        guard daemonUnhealthy else { return false }
        if let last, now.timeIntervalSince(last) < interval { return false }
        last = now
        return true
    }
}
