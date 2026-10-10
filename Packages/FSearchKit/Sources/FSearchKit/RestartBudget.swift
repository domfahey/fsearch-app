/// How many times the app may restart the daemon during one outage.
/// Spent on each disconnect; refilled when results arrive again.
public struct RestartBudget: Equatable, Sendable {
    public let max: Int
    public private(set) var used = 0

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
