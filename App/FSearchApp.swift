import SwiftUI

@main
struct FSearchApp: App {
    @StateObject private var app: AppState

    init() {
        LaunchOptions.current.configureHost()
        let state = AppState.live()
        _app = StateObject(wrappedValue: state)
        // Hosting unit tests: start nothing (no helper, hotkey, onboarding or Sparkle).
        guard !state.options.unitTestHost else { return }
        Updater.start()
        DispatchQueue.main.async {
            PanelController.shared.install(app: state)
            OnboardingLauncher.launch(app: state)
        }
    }

    /// No menu-bar item while hosting unit tests; UI tests (test mode) click it, so it stays there.
    static func showsMenuBarItem(_ options: LaunchOptions) -> Bool { !options.unitTestHost }

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(Self.showsMenuBarItem(app.options))) {
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
        DebugMenuItem(app: app)
        FinishSetupMenuItem(app: app)
        Menu("Help") {
            ForEach(HelpLinks.items, id: \.title) { item in
                Button(item.title) { FileActions.workspace.open(item.url) }
            }
            Divider()
            Button(HelpLinks.reportTitle) { HelpLinks.reportIssue(daemon: app.daemon, workspace: FileActions.workspace) }
        }
        Button("About FSearch") {
            AppActivation.activate(); NSApp.orderFrontStandardAboutPanel(nil)
        }
        SettingsLink { Text("Settings…") }
        CheckForUpdatesItem()
        Button("Quit FSearch") { NSApp.terminate(nil) }
    }
}
