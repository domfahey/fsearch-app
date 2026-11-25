import FSearchKit
import Foundation

/// The Help menu: titles and the pages they open.
enum HelpLinks {
    /// Where the Help pages live; the links open the rendered Markdown on GitHub.
    static let repo = "https://github.com/domfahey/fsearch-app"
    static let base = repo + "/blob/main/"

    /// A Help menu entry.
    struct Item: Equatable {
        /// Stable identifier used for internal lookup independent of localization.
        let id: String
        let title: String
        let url: URL
    }

    /// The Help menu entries, in menu order.
    static let items: [Item] = [
        Item(id: "FSearch Help", title: String(localized: "FSearch Help"), url: URL(string: base + "docs/README.md")!),
        Item(
            id: "Keyboard Shortcuts", title: String(localized: "Keyboard Shortcuts"),
            url: URL(string: base + "docs/reference/keyboard-shortcuts.md")!),
        Item(
            id: "Query Syntax", title: String(localized: "Query Syntax"),
            url: URL(string: base + "docs/reference/query-syntax.md")!),
        Item(id: "Changelog", title: String(localized: "Changelog"), url: URL(string: base + "CHANGELOG.md")!),
        Item(id: "Privacy", title: String(localized: "Privacy"), url: URL(string: base + "docs/privacy.md")!),
    ]

    /// The project's own pages on GitHub, below the Help pages.
    static let community: [Item] = [
        Item(id: "GitHub", title: "GitHub", url: URL(string: repo)!),
        Item(id: "Discussions", title: String(localized: "Discussions"), url: URL(string: repo + "/discussions")!),
    ]

    /// The entry with this stable id (or display title), so the panel's FSearch menu opens the same pages as the menu bar.
    static func item(_ key: String) -> Item? {
        (items + community).first { $0.id == key || $0.title == key }
    }

    /// The title of the menu item that opens the pre-filled bug report.
    static let reportTitle = String(localized: "Report an Issue…")

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
