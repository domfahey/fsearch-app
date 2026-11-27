import Foundation

/// Where the app runs from. A translocated copy (opened straight from a
/// download) or one on a read-only volume (the DMG) must not register the
/// helper: the login item would point into a path that goes away.
public enum InstallLocation {
    /// Why the current bundle location cannot safely register the background helper.
    public enum Problem: Equatable, Sendable {
        case translocated, readOnlyVolume

        /// Localized explanation shown in the "Move FSearch to Applications" alert.
        public var message: String {
            switch self {
            case .translocated:
                String(
                    localized:
                        "FSearch is running from a temporary location macOS made for it, so its background helper can't stay registered. Choose Move to Applications to copy FSearch to your Applications folder and reopen it from there.",
                    bundle: .module)
            case .readOnlyVolume:
                String(
                    localized:
                        "FSearch is running from the disk image, so its background helper can't stay registered. Choose Move to Applications to copy FSearch to your Applications folder and reopen it from there.",
                    bundle: .module)
            }
        }
    }

    /// Returns the install-location problem for `bundlePath`, or nil when it is safe to run from there.
    public static func problem(bundlePath: String, translocated: Bool, readOnlyVolume: Bool) -> Problem? {
        if translocated || bundlePath.contains("/AppTranslocation/") { return .translocated }
        return readOnlyVolume ? .readOnlyVolume : nil
    }
}

/// One FSearch at a time: two would both register helpers and hotkeys.
public enum SingleInstance {
    /// Another running copy among `pids` (processes with our bundle id).
    public static func other(pids: [Int32], me: Int32) -> Int32? { pids.first { $0 != me } }
}
