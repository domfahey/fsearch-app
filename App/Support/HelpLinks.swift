import AppKit
import FSearchKit
import Foundation

/// The Help menu: titles and the pages they open.
enum HelpLinks {
    /// Where the Help pages live; the links open the rendered Markdown on GitHub.
    static let base = "https://github.com/domfahey/fsearch-app/blob/main/"

    /// A Help menu entry.
    struct Item: Equatable { let title: String; let url: URL }

    /// The Help menu entries, in menu order.
    static let items: [Item] = [
        ("FSearch Help", "docs/README.md"),
        ("Keyboard Shortcuts", "docs/reference/keyboard-shortcuts.md"),
        ("Query Syntax", "docs/reference/query-syntax.md"),
        ("Changelog", "CHANGELOG.md"),
        ("Privacy", "docs/privacy.md"),
    ].map { Item(title: $0.0, url: URL(string: base + $0.1)!) }

    /// The title of the menu item that opens the pre-filled bug report.
    static let reportTitle = "Report an Issue…"

    /// The facts for the report. Nothing private: versions, chip, daemon kind and state.
    @MainActor
    static func issueFacts(daemon: DaemonManager) -> IssueReport {
        let info = Bundle.main.infoDictionary
        let state: IssueReport.DaemonSummary =
            switch daemon.state {
            case .checking: .checking
            case .running: .running
            case .indexing: .indexing
            case .needsApproval: .needsApproval
            case .failed: .failed
            }
        return IssueReport(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info?["CFBundleVersion"] as? String ?? "",
            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            chip: IssueReport.chip(machine: machine()),
            daemonInstall: install(owns: daemon.ownsDaemon, state: state),
            daemonState: state)
    }

    /// Ours if we registered it; otherwise a daemon that answers is the CLI's.
    static func install(owns: Bool, state: IssueReport.DaemonSummary) -> IssueReport.DaemonInstall {
        if owns { return .bundled }
        return state == .running || state == .indexing ? .cli : .unsure
    }

    /// The `hw.machine` sysctl value ("arm64" or "x86_64"); the usual two-call sysctl, size first and then the value.
    private static func machine() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &buf, &size, nil, 0)
        return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    @MainActor
    /// Opens the pre-filled new-issue page in the browser; nothing is sent until the user submits the form.
    static func reportIssue(daemon: DaemonManager, workspace: Workspace) {
        workspace.open(IssueReport.url(for: issueFacts(daemon: daemon)))
    }
}
