import Foundation

public enum PanelKey: Equatable, Sendable {
    case up, down, enter, cmdEnter, cmdY, cmdShiftC, cmdDigit(Int), cmdK, escape, backspaceOnEmpty

    /// The ⌘-letter bindings, matched ignoring case: Caps Lock or Shift change the character.
    public static func commandLetter(_ character: String, shift: Bool) -> PanelKey? {
        switch (character.lowercased(), shift) {
        case ("y", false): .cmdY
        case ("k", false): .cmdK
        case ("c", true): .cmdShiftC
        default: nil
        }
    }
}

/// The ⌘K menu's entries and what the panel does after each.
public enum MenuAction: CaseIterable, Hashable, Sendable {
    case open, openWith, reveal, quickLook, copyPath, copyFile, openTerminal, trash

    /// Actions that take you to another app put the launcher away, as ↵ does.
    public var hidesPanel: Bool {
        switch self {
        case .open, .openWith, .reveal, .openTerminal: true
        case .quickLook, .copyPath, .copyFile, .trash: false
        }
    }

    /// An action that failed straight away keeps the launcher up so its error line can be read.
    public func hidesPanel(errored: Bool) -> Bool { hidesPanel && !errored }

    /// Opening a file, in any app, makes it a recent.
    public var recordsRecent: Bool { self == .open || self == .openWith }
}

public enum PanelEffect: Equatable, Sendable {
    case none, open(Int), reveal(Int), quickLook(Int), copyPath(Int), showActions(Int), hide
}

public struct PanelState: Equatable, Sendable {
    public var query: String
    public var mode: SearchMode
    public var selection: Int
    /// Every selectable row, the commands and "use with..." rows included.
    public var count: Int
    /// The file (result) rows, which come first and are the only ones ⌘1–9 open; nil means all rows are files.
    public var files: Int?
    public init(query: String = "", mode: SearchMode = .names, selection: Int = 0, count: Int = 0, files: Int? = nil) {
        (self.query, self.mode, self.selection, self.count, self.files) = (query, mode, selection, count, files)
    }
}

/// What a key does to the panel. No UI involved, so every binding is testable.
public func reduce(_ s: inout PanelState, _ key: PanelKey) -> PanelEffect {
    // Never act on a row that does not exist.
    s.selection = min(max(0, s.selection), max(0, s.count - 1))
    let has = s.count > 0
    switch key {
    case .up: s.selection = max(0, s.selection - 1); return .none
    case .down: s.selection = min(max(0, s.count - 1), s.selection + 1); return .none
    case .enter: return has ? .open(s.selection) : .none
    case .cmdEnter: return has ? .reveal(s.selection) : .none
    case .cmdY: return has ? .quickLook(s.selection) : .none
    case .cmdShiftC: return has ? .copyPath(s.selection) : .none
    case .cmdK: return has ? .showActions(s.selection) : .none
    // ⌘N opens the Nth file; it never lands on a command or "use with..." row.
    case let .cmdDigit(n):
        let files = min(s.count, s.files ?? s.count)
        return (1...9).contains(n) && n <= files ? .open(n - 1) : .none
    case .escape:
        // Clear the query, then drop the content/symbols chip, then hide.
        if !s.query.isEmpty { s.query = ""; s.selection = 0; return .none }
        if s.mode != .names { s.mode = .names; return .none }
        return .hide
    case .backspaceOnEmpty:
        guard s.query.isEmpty else { return .none }
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
