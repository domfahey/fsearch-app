import Foundation

/// The non-private facts "Report an Issue…" pre-fills into the bug-report form.
/// Nothing here is a path, a query or a file name. Nothing is sent: the URL
/// opens a GitHub form the user reviews first.
public struct IssueReport: Equatable, Sendable {
    public enum Chip: String, Sendable { case appleSilicon = "Apple silicon", intel = "Intel" }
    public enum DaemonInstall: String, Sendable {
        case bundled = "Bundled with the app"
        case cli = "CLI (fsearch install --login)"
        case unsure = "Not sure"
    }
    public enum DaemonSummary: String, Sendable {
        case checking, running, indexing, needsApproval, failed
    }

    public var appVersion: String
    public var build: String
    public var macOS: String
    public var chip: Chip?
    public var daemonInstall: DaemonInstall
    public var daemonState: DaemonSummary

    public init(
        appVersion: String, build: String, macOS: String, chip: Chip?,
        daemonInstall: DaemonInstall, daemonState: DaemonSummary
    ) {
        self.appVersion = appVersion
        self.build = build
        self.macOS = macOS
        self.chip = chip
        self.daemonInstall = daemonInstall
        self.daemonState = daemonState
    }

    /// The chip for a `hw.machine` value ("arm64", "x86_64").
    public static func chip(machine: String) -> Chip? {
        switch machine {
        case "arm64": .appleSilicon
        case "x86_64": .intel
        default: nil
        }
    }

    public static let newIssueBase = "https://github.com/domfahey/fsearch-app/issues/new"

    /// The new-issue URL using bug_report.yml, with its field ids pre-filled.
    public static func url(for facts: IssueReport) -> URL {
        var fields: [(String, String)] = [
            ("template", "bug_report.yml"),
            ("macos", facts.macOS),
            ("app-version", facts.build.isEmpty ? facts.appVersion : "\(facts.appVersion) (\(facts.build))"),
            ("daemon", facts.daemonInstall.rawValue),
            ("index-details", "Daemon state: \(facts.daemonState.rawValue)\n"),
        ]
        if let chip = facts.chip { fields.append(("chip", chip.rawValue)) }
        let query = fields.map { "\($0.0)=\(encode($0.1))" }.joined(separator: "&")
        return URL(string: "\(newIssueBase)?\(query)")!
    }

    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
