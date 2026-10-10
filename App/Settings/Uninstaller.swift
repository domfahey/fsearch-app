import FSearchKit
import Foundation
import KeyboardShortcuts

/// "Remove Background Helper and Data…": undoes what the app set up on this Mac.
/// Never touches a CLI daemon (`mt.nd.fsearch`); the data folder goes only if
/// this app owns the daemon that uses it and no CLI login agent shares it. Every side effect is injected.
///
/// What it removes: the helper and the "Open at login" registrations, the app's defaults
/// (including Sparkle's) and shortcut, the debug log folder, and, only under the rule above, the
/// data folder (moved to the Trash, so it is recoverable).
///
/// Why the data folder is kept in the other cases: the index there is a daemon's, and it is not the app's to delete if a
/// CLI daemon (or a helper that couldn't be unregistered and may still be writing) uses it. The report says which case applied.
///
/// It cannot remove the app's Full Disk Access grant; the report links to Privacy settings for that.
@MainActor
final class Uninstaller: ObservableObject {
    /// What happened, shown to the user when it finishes.
    struct Report: Equatable {
        /// Things taken away.
        var removed: [String] = []
        /// Things deliberately left, with the reason.
        var kept: [String] = []
        /// Things that should have gone but couldn't.
        var failures: [String] = []
    }

    /// Where the run is.
    enum Phase: Equatable {
        /// Not started, or dismissed.
        case idle
        /// In progress; a second `run` is ignored.
        case running
        /// Finished, with the report.
        case done(Report)
    }

    /// The app's UserDefaults keys; the shortcut is reset separately.
    static let defaultsKeys = [
        "editor", "debugMode", "onboarded", "skippedFullDiskAccess", "dismissedFullDiskAccessReminder", "recentPaths",
        // Sparkle's own.
        "SUEnableAutomaticChecks", "SUHasLaunchedBefore", "SULastCheckTime", "SUSendProfileInfo",
    ]
    /// Privacy settings' Full Disk Access list, where the user removes the entry by hand.
    static let fullDiskAccessURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    /// Where the run is.
    @Published private(set) var phase: Phase = .idle

    private let helper: HelperService?
    private let loginItem: LoginItemService?
    private let workspace: Workspace
    private let defaults: UserDefaults
    private let dataFolder: URL
    private let logFolder: URL
    private let exists: (URL) -> Bool
    private let cliAgentInstalled: () -> Bool
    private let resetShortcut: () -> Void

    /// Creates an uninstaller.
    ///
    /// - Parameters:
    ///   - helper: The helper's login item, or nil in test mode.
    ///   - loginItem: The app's own login item, or nil in test mode.
    ///   - workspace: Moves folders to the Trash.
    ///   - defaults: Where the app's settings live.
    ///   - dataFolder: The daemon's data folder.
    ///   - logFolder: The debug log's folder.
    ///   - exists: Whether a folder exists.
    ///   - cliAgentInstalled: Whether the CLI's login agent exists.
    ///   - resetShortcut: Clears the global shortcut.
    init(
        helper: HelperService?, loginItem: LoginItemService?, workspace: Workspace, defaults: UserDefaults,
        dataFolder: URL, logFolder: URL,
        exists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        cliAgentInstalled: @escaping () -> Bool = { FileManager.default.fileExists(atPath: DaemonManager.cliAgentPlist.path) },
        resetShortcut: @escaping () -> Void
    ) {
        self.helper = helper
        self.loginItem = loginItem
        self.workspace = workspace
        self.defaults = defaults
        self.dataFolder = dataFolder
        self.logFolder = logFolder
        self.exists = exists
        self.cliAgentInstalled = cliAgentInstalled
        self.resetShortcut = resetShortcut
    }

    /// The running app's: the real helper, login item, Trash and defaults (none of the first two in test mode).
    static func live(options: LaunchOptions) -> Uninstaller {
        Uninstaller(
            helper: options.testMode ? nil : SMAppHelperService(),
            loginItem: options.testMode ? nil : SMAppLoginItemService(),
            workspace: FileActions.workspace, defaults: AppDefaults.store,
            dataFolder: DebugFormat.dataDir(socketPath: options.socketPath),
            logFolder: options.searchLogFile.deletingLastPathComponent(),
            resetShortcut: { KeyboardShortcuts.reset(.togglePanel) })
    }

    /// `ownsDaemon`: DaemonManager.ownsDaemon, read before anything is unregistered.
    /// The helper is unregistered whenever it is registered at all (enabled or
    /// awaiting approval); the data folder is trashed only when this app ran
    /// the daemon, the helper is gone, and no CLI login agent shares the folder.
    func run(ownsDaemon: Bool) async {
        guard phase != .running else { return }
        phase = .running
        var r = Report()
        var helperGone = true

        if let helper, helper.status == .enabled || helper.status == .requiresApproval {
            do {
                try await helper.unregister()
                r.removed.append("The background helper (search index service)")
            } catch {
                helperGone = false
                r.failures.append("Couldn't remove the background helper: \(error.localizedDescription)")
            }
        }

        if let loginItem, loginItem.status == .enabled || loginItem.status == .requiresApproval {
            do {
                try await loginItem.unregister()
                r.removed.append("Open FSearch at login")
            } catch {
                r.failures.append("Couldn't turn off Open at login: \(error.localizedDescription)")
            }
        }

        if cliAgentInstalled() {
            r.kept.append(
                "The data folder (\(dataFolder.path)) was left alone: the fsearch command-line tool's login agent (mt.nd.fsearch) is installed and its daemon uses the same index."
            )
        } else if !ownsDaemon {
            r.kept.append(
                "The data folder (\(dataFolder.path)) was left alone: this app's background helper wasn't enabled, so the index there wasn't the app's to remove."
            )
        } else if helperGone {
            trash(dataFolder, "The index and data folder", into: &r)
        } else {
            r.kept.append("The data folder was left in place because the helper is still registered.")
        }
        if logFolder != dataFolder { trash(logFolder, "The debug search log", into: &r) }

        for key in Self.defaultsKeys { defaults.removeObject(forKey: key) }
        resetShortcut()
        r.removed.append("The app's settings and recent files")

        phase = .done(r)
    }

    /// Trashes a folder if it exists, recording the outcome in the report.
    private func trash(_ url: URL, _ what: String, into r: inout Report) {
        guard exists(url) else { return }
        do {
            try workspace.trash(url)
            r.removed.append("\(what), moved to the Trash")
        } catch {
            r.failures.append("Couldn't move \(url.path) to the Trash: \(error.localizedDescription)")
        }
    }

    /// Opens the Full Disk Access list.
    func openFullDiskAccess() { workspace.open(Self.fullDiskAccessURL) }
    /// Closes the report.
    func dismiss() { phase = .idle }
}
