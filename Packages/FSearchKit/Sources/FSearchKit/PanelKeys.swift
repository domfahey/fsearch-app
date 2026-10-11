import Foundation

/// A key the panel handles itself, independent of AppKit so ``PanelState/reduce(_:)`` is testable.
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
    /// Opens or closes the FSearch menu (⌘/); the panel's rows never see it.
    case appMenu

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

    /// ANSI key codes (Carbon's kVK_ANSI_Y, _K, _C) for the bound letters.
    static let letterKeyCodes: [UInt16: String] = [0x10: "y", 0x28: "k", 0x08: "c"]

    /// The character decides when it is an ASCII letter (QWERTY, Dvorak, AZERTY
    /// all type Latin letters with ⌘). On a non-Latin layout (Russian, Greek)
    /// ⌘Y types "н" or "ν", so then the physical key decides, as macOS's own
    /// menus do.
    public static func commandLetter(_ character: String, shift: Bool, keyCode: UInt16?) -> PanelKey? {
        let isLatinLetter = character.count == 1 && character.unicodeScalars.allSatisfy { $0.isASCII && $0.properties.isAlphabetic }
        if isLatinLetter || character.isEmpty && keyCode == nil { return commandLetter(character, shift: shift) }
        guard let code = keyCode, let letter = letterKeyCodes[code] else { return nil }
        return commandLetter(letter, shift: shift)
    }

    /// Keys that act on a result row, so they must wait for results that
    /// answer the current query (see `HeldKey`). Moving and Escape never wait.
    public var actsOnResults: Bool {
        switch self {
        case .enter, .cmdEnter, .cmdY, .cmdShiftC, .cmdDigit, .cmdK: true
        case .up, .down, .escape, .backspaceOnEmpty, .appMenu: false
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

/// What the panel's owner must do after ``PanelState/reduce(_:)``; row payloads are row indices (see ``PanelRows``).
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

/// The panel's keyboard-relevant state, reduced by ``PanelState/reduce(_:)``.
public struct PanelState: Equatable, Sendable {
    /// The text in the search field.
    public var query: String
    /// Names, content or symbols.
    public var mode: SearchMode
    /// The selected row index; clamped to the rows by ``PanelState/reduce(_:)``.
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

extension PanelState {
    /// What a key does to the panel. No UI involved, so every binding is testable.
    ///
    /// Updates the state in place (selection, query, mode).
    ///
    /// - Parameter key: The key pressed.
    /// - Returns: The side effect the caller must perform, if any.
    public mutating func reduce(_ key: PanelKey) -> PanelEffect {
        // Never act on a row that does not exist.
        self.selection = min(max(0, self.selection), max(0, self.count - 1))
        let has = self.count > 0
        switch key {
        case .up: self.selection = max(0, self.selection - 1); return .none
        case .down: self.selection = min(max(0, self.count - 1), self.selection + 1); return .none
        case .enter: return has ? .open(self.selection) : .none
        case .cmdEnter: return has ? .reveal(self.selection) : .none
        case .cmdY: return has ? .quickLook(self.selection) : .none
        case .cmdShiftC: return has ? .copyPath(self.selection) : .none
        case .cmdK: return has ? .showActions(self.selection) : .none
        // ⌘N opens the Nth file; it never lands on a command or "use with..." row.
        case let .cmdDigit(n):
            let files = min(self.count, self.files ?? self.count)
            return (1...9).contains(n) && n <= files ? .open(n - 1) : .none
        case .escape:
            // Clear the query, then drop the content/symbols chip, then hide.
            if !self.query.isEmpty { self.query = ""; self.selection = 0; return .none }
            if self.mode != .names { self.mode = .names; return .none }
            return .hide
        case .backspaceOnEmpty:
            guard self.query.isEmpty else { return .none }
            self.mode = .names
            return .none
        // The view opens the FSearch menu; the rows don't change.
        case .appMenu: return .none
        }
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

/// A result key (↵, ⌘↵, ⌘Y, ⌘K, ⌘⇧C, ⌘1–9) pressed while the rows still
/// answer an older query or mode (paste + ↵, ↵ while a slow grep runs) is held,
/// not run on the stale rows, and replayed once results for that same query and
/// mode arrive. A newer result key replaces it; a different query or mode, or
/// Escape, drops it.
public struct HeldKey: Equatable, Sendable {
    public private(set) var held: PanelKey?
    private var query = ""
    private var mode: SearchMode = .names

    public init() {}

    /// The key to act on now, or nil if it is held. `current` says whether the
    /// rows answer `query` in `mode`.
    public mutating func press(_ key: PanelKey, current: Bool, query: String, mode: SearchMode) -> PanelKey? {
        if key == .escape { cancel() }
        guard key.actsOnResults, !current else { return key }
        (held, self.query, self.mode) = (key, query, mode)
        return nil
    }

    /// Results arrived for `query` in `mode`: the held key to replay, if it was held for them.
    public mutating func resultsArrived(query: String, mode: SearchMode) -> PanelKey? {
        defer { cancel() }
        return query == self.query && mode == self.mode ? held : nil
    }

    public mutating func cancel() { held = nil }
}
