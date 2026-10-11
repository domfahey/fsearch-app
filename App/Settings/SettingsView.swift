import AppKit
import FSearchKit
import KeyboardShortcuts
import SwiftUI

/// The Settings window: shortcut, editor, login item, updates, debug mode and uninstall.
struct SettingsView: View {
    @EnvironmentObject var app: AppState
    /// Editor.rawValue, "" = none: the same key as AppState.editorRaw (read as AppState.editor).
    @AppStorage("editor", store: AppDefaults.store) private var editor = ""
    @Environment(\.dismissWindow) private var dismissWindow
    @StateObject private var loginItem = LoginItemModel(
        service: LaunchOptions.current.testMode ? nil : SMAppLoginItemService())
    @StateObject private var uninstaller = Uninstaller.live(options: .current)
    @State private var confirming = false

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Shortcut:", name: .togglePanel)
            Picker("Open content results in:", selection: $editor) {
                Text("Default app").tag("")
                ForEach(Editor.installed { FileActions.workspace.urlForApplication(withBundleIdentifier: $0) }, id: \.0) { e, _ in
                    Text(e.displayName).tag(e.rawValue)
                }
            }
            Toggle("Debug mode", isOn: debugBinding)
            Text("Debug mode shows index details and records searches on this Mac only (last 10,000).")
                .font(.caption).foregroundStyle(.secondary)
            loginSection
            UpdatesSettingsSection()
            Section { removeSection }
        }
        .padding(20).frame(width: 440)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
    }

    @ViewBuilder private var loginSection: some View {
        Toggle(
            "Open FSearch at login",
            isOn: Binding(
                get: { loginItem.isOn },
                set: { on in Task { await loginItem.set(on) } }
            )
        )
        .disabled(loginItem.display == .unavailable)
        Text(loginItem.statusText).font(.caption).foregroundStyle(.secondary)
        if loginItem.display == .needsApproval {
            Button("Open Login Items…") { loginItem.openLoginItems() }
        }
        if let error = loginItem.error {
            Text(error).font(.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder private var removeSection: some View {
        switch uninstaller.phase {
        case .idle:
            Button("Remove Background Helper and Data…", role: .destructive) { confirming = true }
                .disabled(app.options.testMode)
                .confirmationDialog("Remove FSearch's background helper and data?", isPresented: $confirming) {
                    Button("Remove", role: .destructive) {
                        let ownership = app.daemon.dataOwnership
                        Task { await uninstaller.run(ownership: ownership) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "This turns off FSearch's background helper and moves its logs and settings to the Trash, and its index too when only this app's helper uses it. A separately installed fsearch command-line tool is left alone. You can undo it from the Trash."
                    )
                }
        case .running:
            ProgressView("Removing…").controlSize(.small)
        case let .done(report):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(report.removed, id: \.self) { Label($0, systemImage: "checkmark.circle") }
                ForEach(report.kept, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                ForEach(report.failures, id: \.self) { Text($0).font(.caption).foregroundStyle(.red) }
                Text("Full Disk Access can't be removed by an app. Remove FSearch from the list by hand, then quit and delete FSearch.app.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Open Full Disk Access…") { uninstaller.openFullDiskAccess() }
                    Button("Done") { uninstaller.dismiss() }
                }
            }
        }
    }

    /// Turning debug mode off also deletes the search log and closes the debug windows.
    private var debugBinding: Binding<Bool> {
        Binding(
            get: { app.debugMode },
            set: { on in DebugMode.set(on, app: app, dismiss: dismissWindow) }
        )
    }
}
