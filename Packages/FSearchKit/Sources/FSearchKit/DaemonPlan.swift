import Foundation

/// What the app does at launch. It never stops or replaces a daemon it didn't
/// start: one that already answers (e.g. a CLI install's) is used, and a CLI
/// login agent that is only briefly down is waited for. Only when nothing
/// answers does it register the bundled helper, and never again once it is
/// enabled. (A registered helper can't take over either: the daemon exits
/// when another one holds the socket lock.)
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
    /// With a CLI login agent installed, its daemon gets longer to come back.
    public static let cliRecheckWindow: Duration = .seconds(10)

    public static func recheckWindow(cliAgentInstalled: Bool) -> Duration {
        cliAgentInstalled ? cliRecheckWindow : recheckWindow
    }

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

    /// After the bounded re-ping of `.recheckThenRegister`.
    public static func afterRecheck(existingAnswers: Bool, ownStatus: ServiceStatus) -> DaemonPlan {
        if existingAnswers { return .useExisting }
        return ownStatus == .requiresApproval ? .needsApproval : .registerBundled
    }

    /// After a successful `register()`.
    public static func afterRegister(ownStatus: ServiceStatus) -> DaemonPlan {
        ownStatus == .requiresApproval ? .needsApproval : .refreshOwn
    }
}

public extension DaemonPlan {
    enum RestartAction: Equatable, Sendable { case refreshOnly, reregister, start }
    /// The app only restarts a daemon it owns; any other that answers (a CLI
    /// install's, a test daemon) is left running. When nothing answers and
    /// nothing is ours, it starts one the way launch does (`start()` rechecks
    /// first, so a CLI daemon coming back still wins).
    static func restartAction(owns: Bool, answers: Bool) -> RestartAction {
        if owns { return .reregister }
        return answers ? .refreshOnly : .start
    }

    /// Whether the daemon is ours: our login item is enabled and the socket
    /// isn't held by some other daemon (our helper yields to a CLI agent's).
    static func owns(helperEnabled: Bool, holder: SocketHolder) -> Bool {
        helperEnabled && holder != .other
    }

    enum HelperUpdate: Equatable, Sendable { case nothing, store, restartThenStore }
    /// After launch: a helper of ours still running an older binary (the app
    /// was updated under it) is restarted once. `stored` is the identity last
    /// seen running, `current` the bundled binary's. A helper registered just
    /// now already runs the current binary.
    static func helperUpdate(owns: Bool, justRegistered: Bool, stored: String?, current: String?) -> HelperUpdate {
        guard owns, let current, stored != current else { return .nothing }
        return justRegistered ? .store : .restartThenStore
    }

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
