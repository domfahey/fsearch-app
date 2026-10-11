import Foundation

/// Where the app keeps its settings (Recents, editor, debug mode, onboarded,
/// the Full Disk Access flags). Test mode (UI tests, `-FSEARCH_SOCKET`, and the
/// unit-test host) uses a throwaway suite, emptied at launch, so a test never
/// reads or writes the user's real `com.domfahey.fsearch` defaults. Launch
/// arguments such as `-debugMode YES` still apply: the argument domain is
/// shared by every suite.
///
/// Not covered: AppKit's window-frame autosave and KeyboardShortcuts write to
/// `UserDefaults.standard`, which a test-mode app still shares with the real
/// app because both have the same bundle id.
enum AppDefaults {
    /// Matches the sweep in scripts/coverage.sh and scripts/ui-smoke.sh.
    static let testSuiteName = "com.domfahey.fsearch.apptests.testmode"

    /// The defaults every part of the app reads and writes: the real ones, or the throwaway suite in test mode.
    // UserDefaults is thread-safe; the SDK just doesn't mark it Sendable.
    nonisolated(unsafe) static let store: UserDefaults = make(testMode: LaunchOptions.current.testMode)

    /// Picks the store for a launch.
    ///
    /// - Parameters:
    ///   - testMode: Whether this is a UI-test launch or the unit-test host.
    ///   - suiteName: The throwaway suite to use in test mode.
    /// - Returns: `.standard` outside test mode; otherwise the suite, emptied first so no state leaks between runs.
    static func make(testMode: Bool, suiteName: String = testSuiteName) -> UserDefaults {
        guard testMode, let d = UserDefaults(suiteName: suiteName) else { return .standard }
        d.removePersistentDomain(forName: suiteName)
        return d
    }
}
