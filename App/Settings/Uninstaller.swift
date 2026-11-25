import FSearchKit
import Foundation
import KeyboardShortcuts

/// "Remove Background Helper and Data…": undoes what the app set up on this Mac.
/// Never touches a CLI daemon (`mt.nd.fsearch`); the data folder goes only if
/// this app's helper positively holds it and no CLI login agent shares it. Every side effect is injected.
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
    /// `DaemonManager.recoverySuspendedKey` is left out on purpose: removal sets it, and wiping
    /// these keys must not turn automatic recovery back on.
    static let defaultsKeys = [
        "editor", "debugMode", "onboarded", "skippedFullDiskAccess", "dismissedFullDiskAccessReminder", "recentPaths",
        "helperIdentity", "updateReminderVisible",
        // Sparkle's own.
        "SUEnableAutomaticChecks", "SUHasLaunchedBefore", "SULastCheckTime", "SUSendProfileInfo",
        "SUAutomaticallyUpdate", "SUScheduledCheckInterval", "SUSkippedVersion", "SULastProfileSubmissionDate",
        "SUUpdateGroupIdentifier",
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
    private let waitUntilStopped: @MainActor () async -> Void

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
    ///   - waitUntilStopped: Waits briefly for an unregistered helper to exit before trashing `dataFolder`.
    init(
        helper: HelperService?, loginItem: LoginItemService?, workspace: Workspace, defaults: UserDefaults,
        dataFolder: URL, logFolder: URL,
        exists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        cliAgentInstalled: @escaping () -> Bool = { FileManager.default.fileExists(atPath: DaemonManager.cliAgentPlist.path) },
        resetShortcut: @escaping () -> Void,
        waitUntilStopped: @escaping @MainActor () async -> Void = {}
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
        self.waitUntilStopped = waitUntilStopped
    }

    /// The running app's: the real helper, login item, Trash and defaults (none of the first two in test mode).
    static func live(options: LaunchOptions) -> Uninstaller {
        let client = DaemonClient(socketPath: options.socketPath, timeout: 0.5)
        return Uninstaller(
            helper: options.testMode ? nil : SMAppHelperService(),
            loginItem: options.testMode ? nil : SMAppLoginItemService(),
            workspace: FileActions.workspace, defaults: AppDefaults.store,
            dataFolder: DebugFormat.dataDir(socketPath: options.socketPath),
            logFolder: options.searchLogFile.deletingLastPathComponent(),
            resetShortcut: { KeyboardShortcuts.reset(.togglePanel) },
            waitUntilStopped: {
                for _ in 0..<30 {
                    if (try? await client.ping()) == nil { return }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            })
    }

    /// `ownership`: DaemonManager.dataOwnership, read before anything is unregistered.
    /// The helper is unregistered whenever it is registered at all (enabled or
    /// awaiting approval); the data folder is trashed only when this app's
    /// helper held it, the helper is gone, and no CLI login agent shares the folder.
    func run(ownership: DataOwnership, daemon: DaemonManager? = nil) async {
        guard phase != .running else { return }
        phase = .running
        await daemon?.suspendForRemoval()
        defer { daemon?.finishRemoval() }
        var r = Report()
        var helperGone = true
        var unregisteredHelper = false

        if let helper, helper.status == .enabled || helper.status == .requiresApproval {
            do {
                try await helper.unregister()
                unregisteredHelper = true
                r.removed.append(String(localized: "The background helper (search index service)"))
            } catch {
                helperGone = false
                r.failures.append(String(localized: "Couldn't remove the background helper: \(error.localizedDescription)"))
            }
        }

        if let loginItem, loginItem.status == .enabled || loginItem.status == .requiresApproval {
            do {
                try await loginItem.unregister()
                r.removed.append(String(localized: "Open FSearch at login"))
            } catch {
                r.failures.append(String(localized: "Couldn't turn off Open at login: \(error.localizedDescription)"))
            }
        }

        if exists(dataFolder) {
            if cliAgentInstalled() {
                r.kept.append(
                    String(
                        localized:
                            "The data folder (\(dataFolder.path)) was left alone: the fsearch command-line tool's login agent (mt.nd.fsearch) is installed and its daemon uses the same index."
                    )
                )
            } else if let reason = Self.keptReason(ownership) {
                r.kept.append(String(localized: "The data folder (\(dataFolder.path)) was left alone: \(reason)"))
            } else if helperGone {
                if unregisteredHelper { await waitUntilStopped() }
                trash(dataFolder, String(localized: "The index and data folder"), into: &r)
            } else {
                r.kept.append(String(localized: "The data folder was left in place because the helper is still registered."))
            }
        }
        if logFolder != dataFolder { trash(logFolder, String(localized: "The debug search log"), into: &r) }

        for key in Self.defaultsKeys { defaults.removeObject(forKey: key) }
        resetShortcut()
        r.removed.append(String(localized: "The app's settings and recent files"))

        phase = .done(r)
    }

    /// Why the data folder isn't the app's to remove, or nil when it is.
    private static func keptReason(_ ownership: DataOwnership) -> String? {
        switch ownership {
        case .ours: nil
        case .helperOff:
            String(localized: "this app's background helper wasn't enabled, so the index there wasn't the app's to remove.")
        case .otherDaemon:
            String(localized: "another fsearch daemon, not this app's helper, is using the index there.")
        case .unconfirmed:
            String(
                localized:
                    "FSearch couldn't confirm that the daemon using it is this app's helper. If nothing else uses it, move it to the Trash yourself."
            )
        }
    }

    /// Trashes a folder if it exists, recording the outcome in the report.
    private func trash(_ url: URL, _ what: String, into r: inout Report) {
        guard exists(url) else { return }
        do {
            try workspace.trash(url)
            r.removed.append(String(localized: "\(what), moved to the Trash"))
        } catch {
            r.failures.append(String(localized: "Couldn't move \(url.path) to the Trash: \(error.localizedDescription)"))
        }
    }

    /// Opens the Full Disk Access list.
    func openFullDiskAccess() { workspace.open(Self.fullDiskAccessURL) }
    /// Closes the report.
    func dismiss() { phase = .idle }
}
