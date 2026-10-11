import Foundation

/// What a selectable row in the panel is.
public enum PanelRow: Equatable, Sendable {
    /// The Nth file result (also its row index).
    case result(Int)
    /// An app command such as Settings.
    case command(AppCommand)
    /// The "search inside files" fallback.
    case searchInside
    /// The "find definitions" fallback.
    case findDefinitions

    /// The mode a fallback row switches to; nil for results.
    public var mode: SearchMode? {
        switch self {
        case .result, .command: nil
        case .searchInside: .content
        case .findDefinitions: .symbols
        }
    }
}

/// The rows below the search field, in order: files, then app commands, then the two fallbacks.
///
/// That order is a contract: ↵ on the first row opens the top file, and ⌘1–9 open the first nine
/// files only (see ``PanelState/reduce(_:)``), never a command or fallback.
///
/// The two "Use <query> with..." rows come after the files, so the keyboard
/// reaches them: they exist only for a non-blank query in names mode (the
/// same blank check as SearchModel), not for the "?" cheat sheet, and not
/// when the query already searches inside files (`grep:` and friends).
///
/// App commands (typing "settings") come after the files, just above the
/// fallbacks, so ↵ still opens the top file; with no files the command is first.
/// A `.result(i)` is the i-th file and has row index i; every other index here is a row index.
public struct PanelRows: Sendable {
    /// The matching app commands, which sit between the files and the fallbacks.
    public let commands: [AppCommand]
    /// How many file rows come first.
    public let files: Int
    /// Whether the two fallback rows follow the files; decided once per query.
    public let hasFallbacks: Bool
    /// The total number of selectable rows.
    public let count: Int

    /// Lays out the rows.
    ///
    /// - Parameters:
    ///   - files: How many result rows there are.
    ///   - query: The typed query.
    ///   - mode: The current search mode.
    public init(files: Int, query: String, mode: SearchMode) {
        self.files = files
        commands = mode == .names ? AppCommand.matches(query) : []
        hasFallbacks = Self.hasFallbacks(query: query, mode: mode)
        count = commands.count + files + (hasFallbacks ? 2 : 0)
    }

    /// The row at an index.
    ///
    /// - Parameter i: A row index.
    /// - Returns: The row, or nil when out of range.
    public func row(at i: Int) -> PanelRow? {
        guard i >= 0, i < count else { return nil }
        if i < files { return .result(i) }
        let c = i - files
        if c < commands.count { return .command(commands[c]) }
        return c == commands.count ? .searchInside : .findDefinitions
    }

    /// Whether the two fallback rows apply to this query and mode.
    public static func hasFallbacks(query: String, mode: SearchMode) -> Bool {
        mode == .names && !SearchModel.isBlank(query) && !QuerySyntax.isCheatSheet(query) && !QuerySplit.hasContentKey(query)
    }

    /// The row count for a query and result count.
    public static func count(files: Int, query: String, mode: SearchMode) -> Int {
        PanelRows(files: files, query: query, mode: mode).count
    }

    /// The row at an index for a query and result count.
    public static func row(at i: Int, files: Int, query: String, mode: SearchMode) -> PanelRow? {
        PanelRows(files: files, query: query, mode: mode).row(at: i)
    }
}
