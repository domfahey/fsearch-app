import Foundation

/// An app command the panel offers as a row when the query names it, such as
/// "settings" or "window".
public enum AppCommand: Equatable, Identifiable, Sendable, CaseIterable {
    /// Opens the app's Settings window.
    case settings
    /// Opens an Everything-style multi-window search browser.
    case searchWindow

    /// Stable English identifier used for view and accessibility ids (`command-FSearch Settings`), independent of localization.
    public var id: String {
        switch self {
        case .settings: "FSearch Settings"
        case .searchWindow: "New Search Window"
        }
    }

    /// The row title shown in the panel.
    public var title: String {
        switch self {
        case .settings: String(localized: "FSearch Settings", bundle: .module)
        case .searchWindow: String(localized: "New Search Window", bundle: .module)
        }
    }

    /// The SF Symbol name for the row icon.
    public var symbol: String {
        switch self {
        case .settings: "gearshape"
        case .searchWindow: "macwindow.badge.plus"
        }
    }

    /// Words that bring the command up when the query is a prefix of one.
    var keywords: [String] {
        switch self {
        case .settings: ["settings", "preferences", "prefs"]
        case .searchWindow: ["window", "browser", "everything"]
        }
    }

    /// Fewest characters of a query that can match a command, so one stray letter doesn't surface a command row.
    static let minimumQueryLength = 2

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
