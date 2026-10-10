import Foundation

/// What the app does at launch about the search daemon.
///
/// The invariant: the app never takes over. It never stops or replaces a daemon it didn't
/// start: one that already answers (e.g. a CLI install's) is used, and a CLI login agent
/// that is only briefly down is waited for. Only when nothing answers does it register the
/// bundled helper, and never again once it is enabled. (A registered helper can't take over
/// either: the daemon exits when another one holds the socket lock.)
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
    /// With a CLI login agent installed, its daemon gets longer to come back.
    public static let cliRecheckWindow: Duration = .seconds(10)

    /// The recheck window: longer when a CLI login agent is installed.
    public static func recheckWindow(cliAgentInstalled: Bool) -> Duration {
        cliAgentInstalled ? cliRecheckWindow : recheckWindow
    }

    /// Chooses the launch plan.
    ///
    /// - Parameters:
    ///   - existingAnswers: Whether a daemon already answers a ping.
    ///   - ownStatus: The state of the helper bundled with the app.
    ///   - cliAgentInstalled: Whether a CLI login agent (`fsearch install --login`) exists, even if its daemon is briefly down.
    /// - Returns: ``useExisting`` whenever something answers; with a CLI agent installed,
    ///   ``recheckThenRegister`` (a longer window, see ``recheckWindow(cliAgentInstalled:)``),
    ///   so a restarting CLI daemon wins but a leftover plist doesn't leave the app without one.
    public static func decide(existingAnswers: Bool, ownStatus: ServiceStatus, cliAgentInstalled: Bool) -> DaemonPlan {
        if existingAnswers { return .useExisting }
        if ownStatus == .enabled { return .refreshOwn }
        // A CLI agent's daemon, even one restarting, is preferred to asking the
        // user to approve a second daemon; but a leftover plist with nothing
        // behind it (a failed install, a deleted binary) must not leave the app
        // without any daemon, so wait for it, then fall back to ours.
        if cliAgentInstalled { return .recheckThenRegister }
        if ownStatus == .requiresApproval { return .needsApproval }
        return .recheckThenRegister
    }

    /// The plan after the bounded re-ping of `.recheckThenRegister`.
    ///
    /// - Parameters:
    ///   - existingAnswers: Whether a daemon answered during the recheck window.
    ///   - ownStatus: The helper's status; one awaiting approval isn't registered again.
    public static func afterRecheck(existingAnswers: Bool, ownStatus: ServiceStatus) -> DaemonPlan {
        if existingAnswers { return .useExisting }
        return ownStatus == .requiresApproval ? .needsApproval : .registerBundled
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
    /// What a restart request does.
    enum RestartAction: Equatable, Sendable {
        /// Leave the daemon running and re-read its state.
        case refreshOnly
        /// Unregister and register the app's own helper again.
        case reregister
        /// Nothing answers and nothing is ours: start one the way launch does.
        case start
    }
    /// The app only restarts a daemon it owns; any other that answers (a CLI
    /// install's, a test daemon) is left running. When nothing answers and
    /// nothing is ours, it starts one the way launch does (`start()` rechecks
    /// first, so a CLI daemon coming back still wins).
    ///
    /// - Parameters:
    ///   - owns: Whether the daemon is ours (see ``owns(helperEnabled:holder:)``).
    ///   - answers: Whether a daemon answers a ping.
    static func restartAction(owns: Bool, answers: Bool) -> RestartAction {
        if owns { return .reregister }
        return answers ? .refreshOnly : .start
    }

    /// Whether the daemon is ours: our login item is enabled and the socket
    /// isn't held by some other daemon (our helper yields to a CLI agent's).
    ///
    /// - Parameters:
    ///   - helperEnabled: Whether our helper's login item is enabled.
    ///   - holder: Who holds the daemon's socket.
    static func owns(helperEnabled: Bool, holder: SocketHolder) -> Bool {
        helperEnabled && holder != .other
    }

    /// What to do after launch about a helper that may run an older binary.
    enum HelperUpdate: Equatable, Sendable {
        /// Leave it alone.
        case nothing
        /// Just record the current identity.
        case store
        /// Restart our helper once, then record the identity.
        case restartThenStore
    }
    /// After launch: a helper of ours still running an older binary (the app
    /// was updated under it) is restarted once. A helper registered just now
    /// already runs the current binary.
    ///
    /// - Parameters:
    ///   - owns: Whether the daemon is ours; any other is never restarted.
    ///   - justRegistered: Whether launch registered the helper just now.
    ///   - stored: The identity last seen running.
    ///   - current: The bundled binary's identity, nil if unreadable.
    static func helperUpdate(owns: Bool, justRegistered: Bool, stored: String?, current: String?) -> HelperUpdate {
        guard owns, let current, stored != current else { return .nothing }
        return justRegistered ? .store : .restartThenStore
    }

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
