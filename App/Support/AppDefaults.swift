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

    // UserDefaults is thread-safe; the SDK just doesn't mark it Sendable.
    nonisolated(unsafe) static let store: UserDefaults = make(testMode: LaunchOptions.current.testMode)

    static func make(testMode: Bool, suiteName: String = testSuiteName) -> UserDefaults {
        guard testMode, let d = UserDefaults(suiteName: suiteName) else { return .standard }
        d.removePersistentDomain(forName: suiteName)
        return d
    }
}
