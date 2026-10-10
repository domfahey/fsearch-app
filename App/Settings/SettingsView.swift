import AppKit
import FSearchKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    /// Editor.rawValue, "" = none: the same key as AppState.editorRaw (read as AppState.editor).
    @AppStorage("editor") private var editor = ""
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Shortcut:", name: .togglePanel)
            Picker("Open content results in:", selection: $editor) {
                Text("Default app").tag("")
                ForEach(installedEditors { FileActions.workspace.urlForApplication(withBundleIdentifier: $0) }, id: \.0) { e, _ in
                    Text(e.displayName).tag(e.rawValue)
                }
            }
            Toggle("Debug mode", isOn: debugBinding)
            Text("Debug mode shows index details and records searches on this Mac only (last 10,000).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 440)
    }

    /// Turning debug mode off also deletes the search log and closes the debug windows.
    private var debugBinding: Binding<Bool> {
        Binding(
            get: { app.debugMode },
            set: { on in DebugMode.set(on, app: app, dismiss: dismissWindow) }
        )
    }
}
