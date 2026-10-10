import AppKit
import FSearchKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppState
    /// Editor.rawValue, "" = none. Task 11 reads the same key into AppState.editorChoice.
    @AppStorage("editor") private var editor = ""

    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Shortcut:", name: .togglePanel)
            Picker("Open content results in:", selection: $editor) {
                Text("Default app").tag("")
                ForEach(installedEditors { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }, id: \.0) { e, _ in
                    Text(e.displayName).tag(e.rawValue)
                }
            }
            Toggle("Debug mode", isOn: debugBinding)
            Text("Debug mode shows index details and records searches on this Mac only (last 10,000).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 440)
    }

    /// Turning debug mode off also deletes the search log (privacy).
    private var debugBinding: Binding<Bool> {
        Binding(
            get: { app.debugMode },
            set: { on in
                app.debugMode = on
                if !on { app.log.clear() }
            }
        )
    }
}
