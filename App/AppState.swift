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
    /// Editor for content hits: `Editor.rawValue`, "" for none.
    @AppStorage("editor") var editorRaw = ""
    var editor: Editor? {
        get { Editor(rawValue: editorRaw) }
        set { editorRaw = newValue?.rawValue ?? "" }
    }
    /// One-line failure from a file action, shown in the panel footer for a few seconds.
    @Published var actionError: String?
    private var errorClear: Task<Void, Never>?

    /// Bumped by every error, so a caller can tell whether its action reported one.
    private(set) var actionErrorCount = 0

    func showActionError(_ message: String) {
        actionErrorCount += 1
        actionError = message
        // An action that sends you to another app hides the launcher; if it fails
        // afterwards, bring the launcher back (query and selection resume) so the error is seen.
        if !PanelController.shared.isVisible { PanelController.shared.show(app: self) }
        errorClear?.cancel()
        errorClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { self?.actionError = nil }
        }
    }

    init() {
        // Two connections: names and content never wait on each other.
        search = SearchModel(names: DaemonClient(socketPath: Self.socketPath), content: DaemonClient(socketPath: Self.socketPath))
        search.onSearched = { [weak self] e in
            guard let self, self.debugMode else { return }
            self.log.append(e, at: Date())
        }
    }
}
