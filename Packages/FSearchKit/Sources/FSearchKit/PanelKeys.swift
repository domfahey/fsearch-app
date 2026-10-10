import Foundation

public enum PanelKey: Equatable, Sendable {
    case up, down, enter, cmdEnter, cmdY, cmdShiftC, cmdDigit(Int), cmdK, escape, backspaceOnEmpty
}

public enum PanelEffect: Equatable, Sendable {
    case none, open(Int), reveal(Int), quickLook(Int), copyPath(Int), showActions(Int), hide
}

public struct PanelState: Equatable, Sendable {
    public var query: String
    public var mode: SearchMode
    public var selection: Int
    public var count: Int
    public init(query: String = "", mode: SearchMode = .names, selection: Int = 0, count: Int = 0) {
        (self.query, self.mode, self.selection, self.count) = (query, mode, selection, count)
    }
}

/// What a key does to the panel. No UI involved, so every binding is testable.
public func reduce(_ s: inout PanelState, _ key: PanelKey) -> PanelEffect {
    let has = s.count > 0
    switch key {
    case .up: s.selection = max(0, s.selection - 1); return .none
    case .down: s.selection = min(max(0, s.count - 1), s.selection + 1); return .none
    case .enter: return has ? .open(s.selection) : .none
    case .cmdEnter: return has ? .reveal(s.selection) : .none
    case .cmdY: return has ? .quickLook(s.selection) : .none
    case .cmdShiftC: return has ? .copyPath(s.selection) : .none
    case .cmdK: return has ? .showActions(s.selection) : .none
    case let .cmdDigit(n): return (1...9).contains(n) && n <= s.count ? .open(n - 1) : .none
    case .escape:
        // Clear the query, then drop the content/symbols chip, then hide.
        if !s.query.isEmpty { s.query = ""; s.selection = 0; return .none }
        if s.mode != .names { s.mode = .names; return .none }
        return .hide
    case .backspaceOnEmpty:
        s.mode = .names
        return .none
    }
}

/// Reopening within a minute resumes where you left off.
public struct PanelSession: Sendable {
    public static let resumeWindow: TimeInterval = 60
    private var last: (PanelState, Date)?
    public init() {}
    public mutating func hidden(_ s: PanelState, at t: Date) { last = (s, t) }
    public func opened(at t: Date) -> PanelState {
        if let (s, at) = last, t.timeIntervalSince(at) <= Self.resumeWindow { return s }
        return PanelState()
    }
}
