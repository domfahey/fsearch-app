import FSearchKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    /// UI tests pass `-FSEARCH_SOCKET <path>` to point at a throwaway daemon.
    static let socketPath: String = {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "-FSEARCH_SOCKET"), i + 1 < a.count { return a[i + 1] }
        return DaemonClient.defaultSocketPath
    }()
    static var testMode: Bool { CommandLine.arguments.contains("-FSEARCH_SOCKET") }

    let daemon = DaemonManager()
    let search: SearchModel
    let recents = Recents(defaults: .standard)
    let log = SearchLog()
    @AppStorage("debugMode") var debugMode = false
    /// Task 11 wires this to the settings picker.
    var editorChoice: Editor?

    init() {
        // Two connections: names and content never wait on each other.
        search = SearchModel(names: DaemonClient(socketPath: Self.socketPath), content: DaemonClient(socketPath: Self.socketPath))
        search.onSearched = { [weak self] e in
            guard let self, self.debugMode else { return }
            self.log.append(e, at: Date())
        }
    }
}
