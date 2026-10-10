import FSearchKit
import Foundation
import KeyboardShortcuts

/// "Remove Background Helper and Data…": undoes what the app set up on this Mac.
/// Never touches a CLI daemon (`mt.nd.fsearch`); the data folder goes only if
/// this app owns the daemon that uses it. Every side effect is injected.
@MainActor
final class Uninstaller: ObservableObject {
    struct Report: Equatable {
        var removed: [String] = []
        var kept: [String] = []
        var failures: [String] = []
    }

    enum Phase: Equatable { case idle, running, done(Report) }

    /// The app's UserDefaults keys; the shortcut is reset separately.
    static let defaultsKeys = [
        "editor", "debugMode", "onboarded", "skippedFullDiskAccess", "dismissedFullDiskAccessReminder", "recentPaths",
    ]
    static let fullDiskAccessURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    @Published private(set) var phase: Phase = .idle

    private let helper: HelperService?
    private let loginItem: LoginItemService?
    private let workspace: Workspace
    private let defaults: UserDefaults
    private let dataFolder: URL
    private let logFolder: URL
    private let exists: (URL) -> Bool
    private let resetShortcut: () -> Void

    init(
        helper: HelperService?, loginItem: LoginItemService?, workspace: Workspace, defaults: UserDefaults,
        dataFolder: URL, logFolder: URL,
        exists: @escaping (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        resetShortcut: @escaping () -> Void
    ) {
        self.helper = helper
        self.loginItem = loginItem
        self.workspace = workspace
        self.defaults = defaults
        self.dataFolder = dataFolder
        self.logFolder = logFolder
        self.exists = exists
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
    func run(ownsDaemon: Bool) async {
        guard phase != .running else { return }
        phase = .running
        var r = Report()
        var helperGone = true

        if ownsDaemon, let helper {
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

        if ownsDaemon && helperGone {
            trash(dataFolder, "The index and data folder", into: &r)
        } else if !ownsDaemon {
            r.kept.append(
                "The data folder (\(dataFolder.path)) was left alone: its search daemon wasn't started by this app, so it may be in use by the fsearch command-line tool."
            )
        } else {
            r.kept.append("The data folder was left in place because the helper is still registered.")
        }
        if logFolder != dataFolder { trash(logFolder, "The debug search log", into: &r) }

        for key in Self.defaultsKeys { defaults.removeObject(forKey: key) }
        resetShortcut()
        r.removed.append("The app's settings and recent files")

        phase = .done(r)
    }

    private func trash(_ url: URL, _ what: String, into r: inout Report) {
        guard exists(url) else { return }
        do {
            try workspace.trash(url)
            r.removed.append("\(what), moved to the Trash")
        } catch {
            r.failures.append("Couldn't move \(url.path) to the Trash: \(error.localizedDescription)")
        }
    }

    func openFullDiskAccess() { workspace.open(Self.fullDiskAccessURL) }
    func dismiss() { phase = .idle }
}
