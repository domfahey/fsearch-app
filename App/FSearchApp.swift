import SwiftUI

@main
struct FSearchApp: App {
    @StateObject private var app: AppState

    init() {
        let state = AppState()
        _app = StateObject(wrappedValue: state)
        DispatchQueue.main.async {
            PanelController.shared.install(app: state)
            Task { await state.daemon.start() }
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
        Window("Welcome to FSearch", id: "onboarding") { OnboardingView().environmentObject(app) }
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
        SettingsLink { Text("Settings…") }
        Button("Quit FSearch") { NSApp.terminate(nil) }
    }
}
