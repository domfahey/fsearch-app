import Foundation

/// An app command the panel offers as a row when the query names it, such as
/// "settings". Only Settings for now; About or Quit would be more cases.
public enum AppCommand: Equatable, Sendable, CaseIterable {
    /// Opens the app's Settings window.
    case settings

    /// The row title shown in the panel.
    public var title: String {
        switch self {
        case .settings: "FSearch Settings"
        }
    }

    /// The SF Symbol name for the row icon.
    public var symbol: String {
        switch self {
        case .settings: "gearshape"
        }
    }

    /// Words that bring the command up when the query is a prefix of one.
    var keywords: [String] {
        switch self {
        case .settings: ["settings", "preferences", "prefs"]
        }
    }

    /// Fewest characters of a query that can match a command, so one stray letter doesn't surface a command row.
    public static let minimumQueryLength = 2

    /// The commands whose keywords the whole trimmed query is a case-insensitive prefix of.
    ///
    /// - Parameter query: The text typed in the panel.
    /// - Returns: The matching commands, or none when the trimmed query is shorter than ``minimumQueryLength``.
    public static func matches(_ query: String) -> [AppCommand] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= minimumQueryLength else { return [] }
        return allCases.filter { $0.keywords.contains { $0.hasPrefix(q) } }
    }
}
