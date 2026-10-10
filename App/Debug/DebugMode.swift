import SwiftUI

/// The one place debug mode is switched, so every path (Settings, the menu)
/// does the same thing: turning it off deletes the search log (privacy) and
/// closes the debug windows.
enum DebugMode {
    static let windowIDs = ["index", "log"]

    @MainActor static func set(_ on: Bool, app: AppState, dismiss: DismissWindowAction?) {
        app.debugMode = on
        guard !on else { return }
        app.log.clear()
        if let dismiss {
            for id in windowIDs { dismiss(id: id) }
        }
    }
}

/// Menu item for MenuContent: `DebugMenuItem(app: app)`.
struct DebugMenuItem: View {
    @ObservedObject var app: AppState
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Button(app.debugMode ? "Turn Off Debug Mode" : "Turn On Debug Mode") {
            DebugMode.set(!app.debugMode, app: app, dismiss: dismissWindow)
        }
        .keyboardShortcut("d", modifiers: [.command, .option])
    }
}
