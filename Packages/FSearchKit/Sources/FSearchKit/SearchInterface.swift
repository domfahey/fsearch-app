import Foundation

/// Which search interface FSearch opens by default for the global shortcut, menu-bar **Search…**,
/// reopening the app, and `fsearch://` links.
public enum SearchInterface: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    /// Classic floating Raycast-style launcher panel (v1).
    case panel
    /// Everything-style multi-window desktop search browser (v2).
    case window

    /// The `UserDefaults` key storing the preferred search interface raw value.
    public static let storageKey = "searchInterface"

    /// Resolves a stored or configured raw value, defaulting to ``panel`` when nil or unrecognized.
    public static func resolve(_ raw: String?) -> SearchInterface {
        raw.flatMap { SearchInterface(rawValue: $0.lowercased()) } ?? .panel
    }

    /// Parses an explicit URL `ui=` override (`panel` or `window`), returning `nil` when unrecognized.
    public static func parseOverride(_ raw: String?) -> SearchInterface? {
        raw.flatMap { SearchInterface(rawValue: $0.lowercased()) }
    }

    /// Localized title shown in Settings.
    public var displayName: String {
        switch self {
        case .panel: String(localized: "Launcher Panel (Classic)", bundle: .module)
        case .window: String(localized: "Search Window (New)", bundle: .module)
        }
    }
}
