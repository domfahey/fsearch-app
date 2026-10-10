import FSearchKit
import Foundation

/// How this process was launched, read once from the command line and environment.
///
/// - Test mode: UI tests pass `-FSEARCH_SOCKET <path>` to point at a throwaway
///   daemon. The app then never touches SMAppService, never shows onboarding,
///   and keeps its search log next to that daemon (in its temp HOME).
/// - Unit-test host: the app is hosting the AppTests bundle. It starts nothing
///   (no helper, no hotkey, no onboarding, no Sparkle) and behaves as test mode
///   with a socket nobody listens on, so no test can reach the real daemon.
///
/// Both hooks exist only in Debug builds. A Release build ignores them, so no
/// other process can switch off the helper and updates (say, by setting
/// XCTestSessionIdentifier with `launchctl setenv`) or point the app at its own socket.
struct LaunchOptions: Equatable, Sendable {
    /// The daemon's socket: `-FSEARCH_SOCKET`, a dead path in the unit-test host, or the real one.
    var socketPath: String
    /// True for UI tests and the unit-test host: nothing here may touch the user's real daemon, defaults or files.
    var testMode: Bool
    /// True when XCTest hosts its bundle in the app.
    var unitTestHost: Bool
    /// `-UITestShowPanel`: open the panel at launch and keep it up without focus.
    var showPanel: Bool
    /// Where the search log goes instead (unit tests point it at a temp folder).
    var searchLogOverride: URL? = nil

    /// The options of this process.
    static let current = parse(arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment)

    /// Whether this build honours the test hooks: Debug only.
    static var testHooksCompiledIn: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    /// Reads the options.
    ///
    /// - Parameters:
    ///   - a: The command-line arguments.
    ///   - env: The environment, searched for XCTest's variables.
    ///   - defaultSocket: The daemon socket when none is given.
    ///   - honorsTestHooks: False (Release builds) ignores every test hook.
    static func parse(
        arguments a: [String], environment env: [String: String], defaultSocket: String = DaemonClient.defaultSocketPath,
        honorsTestHooks: Bool = LaunchOptions.testHooksCompiledIn
    ) -> LaunchOptions {
        guard honorsTestHooks else {
            return LaunchOptions(socketPath: defaultSocket, testMode: false, unitTestHost: false, showPanel: false)
        }
        var socket: String?
        if let i = a.firstIndex(of: "-FSEARCH_SOCKET"), i + 1 < a.count { socket = a[i + 1] }
        let explicitTest = a.contains("-FSEARCH_SOCKET")
        // XCTest sets these in the host app's environment when it injects a test bundle.
        let hosting =
            !explicitTest
            && (env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil || env["XCTestSessionIdentifier"] != nil)
        if hosting && socket == nil {
            socket = NSTemporaryDirectory() + "fsearch-unit-host-\(getpid())/no-daemon.sock"
        }
        return LaunchOptions(
            socketPath: socket ?? defaultSocket, testMode: explicitTest || hosting, unitTestHost: hosting,
            showPanel: a.contains("-UITestShowPanel"))
    }

    /// Debug mode's search log. In test mode it lives in the test daemon's data
    /// folder (inside its temp HOME), never in the user's ~/Library/Logs.
    var searchLogFile: URL {
        if let searchLogOverride { return searchLogOverride }
        if testMode { return DebugFormat.dataDir(socketPath: socketPath).appendingPathComponent("searches.jsonl") }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/FSearch/searches.jsonl")
    }

    /// The unit-test host never reopens windows AppKit saved in an earlier run
    /// (Xcode passes -ApplePersistenceIgnoreState too; this doesn't rely on it).
    /// The registration domain only: nothing is written to disk.
    func configureHost(defaults: UserDefaults = .standard) {
        guard unitTestHost else { return }
        defaults.register(defaults: ["ApplePersistenceIgnoreState": true])
    }
}
