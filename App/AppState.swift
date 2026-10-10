import FSearchKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let options: LaunchOptions
    let daemon: DaemonManager
    let search: SearchModel
    let recents: Recents
    let log: SearchLog
    @AppStorage("debugMode") var debugMode = false
    /// Editor for content hits: `Editor.rawValue`, "" for none.
    @AppStorage("editor") var editorRaw = ""
    var editor: Editor? {
        get { Editor(rawValue: editorRaw) }
        set { editorRaw = newValue?.rawValue ?? "" }
    }
    /// Bumped whenever the recents may have changed (a file opened or trashed),
    /// so the panel re-reads `recents.paths`, which aren't observable themselves.
    @Published private(set) var recentsGeneration = 0
    func recentsChanged() { recentsGeneration += 1 }
    /// Opening a file makes it a recent.
    func openedRecent(_ path: String) {
        recents.opened(path)
        recentsChanged()
    }

    /// One-line failure from a file action, shown in the panel footer for a few seconds.
    @Published var actionError: String?
    private var errorClear: Task<Void, Never>?
    /// How long an action error stays up.
    var actionErrorDuration: Duration = .seconds(5)
    /// Brought back when an action fails while it is hidden.
    var panel: PanelHost = PanelController.shared

    /// Bumped by every error, so a caller can tell whether its action reported one.
    private(set) var actionErrorCount = 0

    func showActionError(_ message: String) {
        actionErrorCount += 1
        actionError = message
        // An action that sends you to another app hides the launcher; if it fails
        // afterwards, bring the launcher back (query and selection resume) so the error is seen.
        if !panel.isVisible { panel.show(app: self) }
        errorClear?.cancel()
        let duration = actionErrorDuration
        errorClear = Task { [weak self] in
            try? await Task.sleep(for: duration)
            if !Task.isCancelled { self?.actionError = nil }
        }
    }

    /// The running app: real daemon connections, real login item (none in test mode).
    static func live(options: LaunchOptions = .current) -> AppState {
        AppState(options: options, defaults: .standard,
                 helper: options.testMode ? nil : SMAppHelperService(),
                 // Two connections: names and content never wait on each other.
                 names: DaemonClient(socketPath: options.socketPath),
                 content: DaemonClient(socketPath: options.socketPath),
                 control: DaemonClient(socketPath: options.socketPath))
    }

    init(options: LaunchOptions, defaults: UserDefaults, helper: HelperService?,
         names: SearchBackend, content: SearchBackend, control: any DaemonControl,
         clock: DaemonClock = .live) {
        self.options = options
        daemon = DaemonManager(client: control, service: helper, clock: clock)
        search = SearchModel(names: names, content: content)
        recents = Recents(defaults: defaults)
        log = SearchLog(file: options.searchLogFile)
        _debugMode = AppStorage(wrappedValue: false, "debugMode", store: defaults)
        _editorRaw = AppStorage(wrappedValue: "", "editor", store: defaults)
        search.onSearched = { [weak self] e in
            guard let self, self.debugMode else { return }
            self.log.append(e, at: Date())
        }
    }
}
