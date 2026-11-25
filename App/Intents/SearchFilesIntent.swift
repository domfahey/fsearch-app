import AppIntents
import FSearchKit
import Foundation
import Synchronization

/// Search scope exposed to Apple Shortcuts' "Search Files" action.
enum SearchModeOption: String, AppEnum {
    case names
    case content
    case symbols

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Search Mode"
    static let caseDisplayRepresentations: [SearchModeOption: DisplayRepresentation] = [
        .names: DisplayRepresentation(title: "File Names", subtitle: "Match file and folder names"),
        .content: DisplayRepresentation(title: "Inside Files", subtitle: "Search text inside files"),
        .symbols: DisplayRepresentation(title: "Definitions", subtitle: "Find symbol definitions in code"),
    ]

    /// Maps the AppEnum choice onto `FSearchKit.SearchMode`.
    var searchMode: SearchMode {
        switch self {
        case .names: .names
        case .content: .content
        case .symbols: .symbols
        }
    }
}

/// Shortcuts action that queries the fsearch daemon in the background and returns matching files.
struct SearchFilesIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Files"
    static let description = IntentDescription(
        "Search indexed files on your Mac by name, file contents, or symbol definitions using FSearch.",
        categoryName: "Search",
        searchKeywords: ["fsearch", "find", "files", "grep", "symbols"]
    )
    static let openAppWhenRun: Bool = false

    @Parameter(
        title: "Query",
        description: "Text or FSearch filters such as ext:pdf, in:~/Developer, or mtime:<7d.",
        requestValueDialog: IntentDialog("What files do you want to search for?")
    )
    var query: String

    @Parameter(title: "Search In", default: .names)
    var mode: SearchModeOption

    @Parameter(title: "Limit", default: 50, controlStyle: .stepper, inclusiveRange: (1, 1000))
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Search \(\.$mode) for \(\.$query)") {
            \.$limit
        }
    }

    /// Creates the default daemon connection using this process's launch options.
    static func defaultBackend() -> SearchBackend {
        DaemonClient(socketPath: LaunchOptions.current.socketPath)
    }

    /// Seam allowing unit tests to supply a fake backend without touching the user's daemon socket.
    static let backendFactory = Mutex<@Sendable () -> SearchBackend>({ defaultBackend() })

    init() {}

    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let backend = Self.backendFactory.withLock { $0 }()
        let paths = try await ShortcutSearch.run(query: query, mode: mode.searchMode, limit: limit, backend: backend)
        let files = paths.map { IntentFile(fileURL: URL(fileURLWithPath: $0)) }
        return .result(value: files)
    }
}

/// Exposes FSearch's actions to Shortcuts and Spotlight.
struct FSearchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SearchFilesIntent(),
            phrases: [
                "Search files in \(.applicationName)",
                "Find files with \(.applicationName)",
            ],
            shortTitle: "Search Files",
            systemImageName: "magnifyingglass"
        )
    }
}
