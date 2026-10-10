import SwiftUI

@main
struct FSearchApp: App {
    @StateObject private var app: AppState

    init() {
        let state = AppState()
        _app = StateObject(wrappedValue: state)
        Updater.start()
        DispatchQueue.main.async {
            PanelController.shared.install(app: state)
            OnboardingLauncher.launch(app: state)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarFixItem(app: app)
            MenuContent(app: app)
        } label: {
            MenuBarLabel(app: app)
        }
        Settings { SettingsView().environmentObject(app) }
        Window("Index Details", id: "index") { IndexDetailsView().environmentObject(app) }
        Window("Search Log", id: "log") { SearchLogView().environmentObject(app) }
    }
}

/// The menu's content lives in its own View so it can read `openWindow`.
struct MenuContent: View {
    @ObservedObject var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Search…") { PanelController.shared.toggle(app: app) }
        Divider()
        if app.debugMode {
            Button("Index Details…") { openWindow(id: "index") }
            Button("Search Log…") { openWindow(id: "log") }
            Divider()
        }
        FinishSetupMenuItem(app: app)
        SettingsLink { Text("Settings…") }
        CheckForUpdatesItem()
        Button("Quit FSearch") { NSApp.terminate(nil) }
    }
}
