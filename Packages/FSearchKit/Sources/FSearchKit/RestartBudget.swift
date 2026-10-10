/// How many times the app may restart the daemon during one outage.
/// Spent on each disconnect; refilled when results arrive again.
public struct RestartBudget: Equatable, Sendable {
    /// The restarts allowed per outage.
    public let max: Int
    /// Restarts spent in this outage.
    public private(set) var used = 0

    /// Creates a full budget.
    ///
    /// - Parameter max: The restarts allowed per outage; the cap stops a crashing daemon from being restarted forever.
    public init(max: Int = 3) { self.max = max }

    /// True (and one restart used) while the outage still has restarts left.
    public mutating func spend() -> Bool {
        guard used < max else { return false }
        used += 1
        return true
    }

    /// Results arrived: the outage is over.
    public mutating func reset() { used = 0 }
}
