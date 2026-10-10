import FSearchKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let daemon = DaemonManager()
    let search: SearchModel
    let recents = Recents(defaults: .standard)
    let log = SearchLog()
    @AppStorage("debugMode") var debugMode = false

    init() {
        // Two connections: names and content never wait on each other.
        search = SearchModel(names: DaemonClient(), content: DaemonClient())
        search.onSearched = { [weak self] e in
            guard let self, self.debugMode else { return }
            self.log.append(e, at: Date())
        }
    }
}
