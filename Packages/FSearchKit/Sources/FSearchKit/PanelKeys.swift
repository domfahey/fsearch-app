import Foundation

/// A key the panel handles itself, independent of AppKit so ``reduce(_:_:)`` is testable.
public enum PanelKey: Equatable, Sendable {
    /// Moves the selection up one row.
    case up
    /// Moves the selection down one row.
    case down
    /// Opens the selected row.
    case enter
    /// Reveals the selected file in Finder (⌘↵).
    case cmdEnter
    /// Quick Look (⌘Y).
    case cmdY
    /// Copies the selected path (⇧⌘C).
    case cmdShiftC
    /// Opens the Nth file (⌘1–9); the payload is the digit.
    case cmdDigit(Int)
    /// Shows the actions menu for the selected row (⌘K).
    case cmdK
    /// Clears the query, then the search mode, then hides the panel.
    case escape
    /// Backspace in an empty field: leaves content/symbols mode.
    case backspaceOnEmpty

    /// The ⌘-letter bindings, matched ignoring case: Caps Lock or Shift change the character.
    ///
    /// - Parameters:
    ///   - character: The key's character.
    ///   - shift: Whether Shift is held; only ⇧⌘C uses it.
    /// - Returns: The key, or nil for an unbound letter.
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
    /// The entries, in menu order.
    case open, openWith, reveal, quickLook, copyPath, copyFile, openTerminal, trash

    /// Whether the action takes you to another app, so the launcher goes away as it does for ↵.
    public var hidesPanel: Bool {
        switch self {
        case .open, .openWith, .reveal, .openTerminal: true
        case .quickLook, .copyPath, .copyFile, .trash: false
        }
    }

    /// An action that failed straight away keeps the launcher up so its error line can be read.
    ///
    /// - Parameter errored: Whether the action failed immediately.
    public func hidesPanel(errored: Bool) -> Bool { hidesPanel && !errored }

    /// Opening a file, in any app, makes it a recent.
    public var recordsRecent: Bool { self == .open || self == .openWith }
}

/// What the panel's owner must do after ``reduce(_:_:)``; row payloads are row indices (see ``PanelRows``).
public enum PanelEffect: Equatable, Sendable {
    /// Nothing beyond the state change.
    case none
    /// Open the row.
    case open(Int)
    /// Reveal the row in Finder.
    case reveal(Int)
    /// Preview the row.
    case quickLook(Int)
    /// Copy the row's path.
    case copyPath(Int)
    /// Show the actions menu for the row.
    case showActions(Int)
    /// Hide the panel.
    case hide
}

/// The panel's keyboard-relevant state, reduced by ``reduce(_:_:)``.
public struct PanelState: Equatable, Sendable {
    /// The text in the search field.
    public var query: String
    /// Names, content or symbols.
    public var mode: SearchMode
    /// The selected row index; clamped to the rows by ``reduce(_:_:)``.
    public var selection: Int
    /// Every selectable row, the commands and "use with..." rows included.
    public var count: Int
    /// The file (result) rows, which come first and are the only ones ⌘1–9 open; nil means all rows are files.
    public var files: Int?
    /// Creates a state; the defaults are an empty panel.
    public init(query: String = "", mode: SearchMode = .names, selection: Int = 0, count: Int = 0, files: Int? = nil) {
        (self.query, self.mode, self.selection, self.count, self.files) = (query, mode, selection, count, files)
    }
}

/// What a key does to the panel. No UI involved, so every binding is testable.
///
/// - Parameters:
///   - s: The state, updated in place (selection, query, mode).
///   - key: The key pressed.
/// - Returns: The side effect the caller must perform, if any.
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
///
/// A longer gap, or no earlier hide, starts from an empty panel.
public struct PanelSession: Sendable {
    /// Seconds after hiding in which reopening restores the old state.
    public static let resumeWindow: TimeInterval = 60
    private var last: (PanelState, Date)?
    /// Creates a session with nothing to resume.
    public init() {}
    /// Records the state at the moment the panel was hidden.
    ///
    /// - Parameters:
    ///   - s: The state to resume.
    ///   - t: When it was hidden.
    public mutating func hidden(_ s: PanelState, at t: Date) { last = (s, t) }
    /// The state to open with.
    ///
    /// - Parameter t: When the panel opens.
    /// - Returns: The remembered state if the panel was hidden at most ``resumeWindow`` seconds ago, else an empty state.
    public func opened(at t: Date) -> PanelState {
        if let (s, at) = last, t.timeIntervalSince(at) <= Self.resumeWindow { return s }
        return PanelState()
    }
}
