import Foundation

/// What a selectable row in the panel is.
public enum PanelRow: Equatable, Sendable {
    case result(Int), searchInside, findDefinitions

    /// The mode a fallback row switches to; nil for results.
    public var mode: SearchMode? {
        switch self {
        case .result: nil
        case .searchInside: .content
        case .findDefinitions: .symbols
        }
    }
}

/// The two "Use <query> with..." rows come after the files, so the keyboard
/// reaches them: they exist only for a non-blank query in names mode (the
/// same blank check as SearchModel), not for the "?" cheat sheet, and not
/// when the query already searches inside files (`grep:` and friends).
public enum PanelRows {
    public static func hasFallbacks(query: String, mode: SearchMode) -> Bool {
        mode == .names && !SearchModel.isBlank(query) && !QuerySyntax.isCheatSheet(query) && !QuerySplit.hasContentKey(query)
    }

    public static func count(files: Int, query: String, mode: SearchMode) -> Int {
        files + (hasFallbacks(query: query, mode: mode) ? 2 : 0)
    }

    public static func row(at i: Int, files: Int, query: String, mode: SearchMode) -> PanelRow? {
        guard i >= 0, i < count(files: files, query: query, mode: mode) else { return nil }
        if i < files { return .result(i) }
        return i == files ? .searchInside : .findDefinitions
    }
}
