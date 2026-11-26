import AppKit
import FSearchKit
import KeyboardShortcuts
import SwiftUI

/// The Settings window: shortcut, editor, login item, updates, debug mode and uninstall.
struct SettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityStyleOverride) private var styleOverride
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var loginItem = LoginItemModel(
        service: LaunchOptions.current.testMode ? nil : SMAppLoginItemService())
    @StateObject private var uninstaller = Uninstaller.live(options: .current)
    @State private var confirming = false
    @State private var shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel)
    private let runningBundleIds: () -> Set<String>

    init() {
        runningBundleIds = { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }
    }

    #if DEBUG
        /// Tests pass the login item, uninstaller and optional running apps list, with fakes behind them.
        init(
            loginItem: LoginItemModel, uninstaller: Uninstaller,
            runningBundleIds: @escaping () -> Set<String> = { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }
        ) {
            _loginItem = StateObject(wrappedValue: loginItem)
            _uninstaller = StateObject(wrappedValue: uninstaller)
            self.runningBundleIds = runningBundleIds
        }
    #endif

    /// Picker entries for the content-results editor: Default app, installed editors, and any previously
    /// chosen editor that is no longer installed so SwiftUI's Picker never holds an unlisted tag.
    static func editorOptions(selected: Editor?, installed: [Editor]) -> [(tag: String, label: String)] {
        var rows: [(String, String)] = [("", String(localized: "Default app"))]
        for e in installed { rows.append((e.rawValue, e.displayName)) }
        if let selected, !installed.contains(selected) {
            rows.append((selected.rawValue, String(localized: "\(selected.displayName) (not installed)")))
        }
        return rows
    }

    var body: some View {
        let installedEditors = Editor.installed { FileActions.workspace.urlForApplication(withBundleIdentifier: $0) }.map(\.0)
        let editorRows = Self.editorOptions(selected: app.editor, installed: installedEditors)
        Form {
            KeyboardShortcuts.Recorder("Shortcut:", name: .togglePanel) { shortcut = $0 }
            if let w = Onboarding.hotkeyWarning(
                defaultIsOptionSpace: shortcut == .init(.space, modifiers: [.option]), runningBundleIds: runningBundleIds())
            {
                Text("⚠ " + w).foregroundStyle(.orange).font(.callout)
                    .accessibilityLabel("Warning: \(w)")
            }
            Picker("Open content results in:", selection: $app.editorRaw) {
                ForEach(editorRows, id: \.tag) { row in
                    Text(row.label).tag(row.tag)
                }
            }
            Toggle("Debug mode", isOn: debugBinding)
            Text("Debug mode shows index details and records searches on this Mac only (last 10,000).")
                .font(.caption).foregroundStyle(.secondary)
            loginSection
            shortcutsSection
            UpdatesSettingsSection()
            Section { removeSection }
        }
        .padding(20).frame(width: 440)
        .respectingReduceMotion(AccessibilityStyle.resolved(override: styleOverride, reduceMotion: reduceMotion).suppressesAnimations)
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
                        Task { await Self.performRemoval(app: app, uninstaller: uninstaller, loginItem: loginItem) }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "This turns off FSearch's background helper, moves its logs to the Trash, and its index too when only this app's helper uses it, and clears the app's settings and shortcut. A separately installed fsearch command-line tool is left alone. You can restore the logs and index from the Trash, but not the settings."
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
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    /// Captures daemon ownership before unregistering, runs the uninstaller, and refreshes the login item state.
    @MainActor
    static func performRemoval(app: AppState, uninstaller: Uninstaller, loginItem: LoginItemModel) async {
        let ownership = app.daemon.dataOwnership
        await uninstaller.run(ownership: ownership, daemon: app.daemon)
        loginItem.refresh()
    }

    /// Turning debug mode off also deletes the search log and closes the debug windows.
    private var debugBinding: Binding<Bool> {
        Binding(
            get: { app.debugMode },
            set: { on in DebugMode.set(on, app: app, dismiss: dismissWindow) }
        )
    }

    /// Opt-in for Shortcuts content searches: the action runs unattended with FSearch's Full Disk Access.
    @ViewBuilder private var shortcutsSection: some View {
        Toggle(isOn: $app.allowShortcutsContentSearch) { Text(SearchFilesIntent.allowContentSearchTitle) }
        Text(
            "Any shortcut could then find files by what they contain, including files it can't open itself. File name searches always work."
        )
        .font(.caption).foregroundStyle(.secondary)
    }
}
