import Foundation

/// The non-private facts "Report an Issue…" pre-fills into the bug-report form.
/// Nothing here is a path, a query or a file name. Nothing is sent: the URL
/// opens a GitHub form the user reviews first.
///
/// The privacy rule is structural: the type has no field that could hold a path, query or
/// file name, so none can reach the URL.
public struct IssueReport: Equatable, Sendable {
    /// The processor family.
    public enum Chip: String, Sendable {
        /// An Apple silicon Mac.
        case appleSilicon = "Apple silicon"
        /// An Intel Mac.
        case intel = "Intel"
    }
    /// How the running daemon was installed; the raw value is the text shown in the form.
    public enum DaemonInstall: String, Sendable {
        /// The helper inside the app.
        case bundled = "Bundled with the app"
        /// A daemon from the `fsearch` command-line tool.
        case cli = "CLI (fsearch install --login)"
        /// Couldn't tell.
        case unsure = "Not sure"
    }
    /// A coarse daemon state; the raw value goes into the form.
    public enum DaemonSummary: String, Sendable {
        /// Still asking the daemon.
        case checking
        /// Answering.
        case running
        /// Building the first index.
        case indexing
        /// Waiting for approval in Login Items.
        case needsApproval
        /// Not answering.
        case failed
    }

    /// The marketing version, such as "1.2.0".
    public var appVersion: String
    /// The build number; empty when unknown.
    public var build: String
    /// The macOS version string.
    public var macOS: String
    /// The processor family, or nil when unrecognized.
    public var chip: Chip?
    /// How the daemon was installed.
    public var daemonInstall: DaemonInstall
    /// The daemon's state at the time of the report.
    public var daemonState: DaemonSummary

    /// Creates the facts for one report.
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

    /// The chip for a `hw.machine` value ("arm64", "x86_64"); nil for anything else.
    ///
    /// - Parameter machine: The `hw.machine` sysctl value.
    public static func chip(machine: String) -> Chip? {
        switch machine {
        case "arm64": .appleSilicon
        case "x86_64": .intel
        default: nil
        }
    }

    /// The repository's new-issue page.
    public static let newIssueBase = "https://github.com/domfahey/fsearch-app/issues/new"

    /// The new-issue URL using bug_report.yml, with its field ids pre-filled.
    ///
    /// The ids must match the form template's. Values are percent-encoded.
    ///
    /// - Parameter facts: What to pre-fill.
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

    /// Characters left as is when percent-encoding a value (RFC 3986 unreserved).
    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
