/// Where the app runs from. A translocated copy (opened straight from a
/// download) or one on a read-only volume (the DMG) must not register the
/// helper: the login item would point into a path that goes away.
public enum InstallLocation {
    public enum Problem: Equatable, Sendable {
        case translocated, readOnlyVolume

        public var message: String {
            switch self {
            case .translocated:
                "FSearch is running from a temporary location macOS made for it. Move FSearch to your Applications folder, then open it from there."
            case .readOnlyVolume:
                "FSearch is running from the disk image. Move FSearch to your Applications folder, then open it from there."
            }
        }
    }

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
