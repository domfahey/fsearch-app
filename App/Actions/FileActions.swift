import AppKit
import FSearchKit
import Quartz
import os

/// Everything the panel does to a file, routed through ``workspace`` so test mode can record instead of act.
@MainActor
enum FileActions {
    /// Where actions go: the real workspace; in test mode one that only records
    /// (UI tests can press ↵ safely); a fake in unit tests.
    static var workspace: Workspace =
        LaunchOptions.current.testMode
        ? TestModeWorkspace(log: TestModeWorkspace.logFile(socketPath: LaunchOptions.current.socketPath))
        : SystemWorkspace()
    /// ⌘⇧C and "Copy File" write here: the general pasteboard, or a private one under test.
    static var pasteboard: NSPasteboard = defaultPasteboard(for: .current)

    /// A private pasteboard in the unit-test host, so a copy made before a test
    /// swaps in its own never reaches the user's clipboard. UI tests (test mode
    /// in the app's own process) read the general pasteboard from the test
    /// runner and restore the user's afterwards, so they keep it.
    static func defaultPasteboard(for options: LaunchOptions) -> NSPasteboard {
        options.unitTestHost ? NSPasteboard(name: NSPasteboard.Name("com.domfahey.fsearch.apptests.host")) : .general
    }

    /// The file URL for a path.
    static func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    /// The editor command for a content hit, if an editor is chosen and installed.
    static func editorCommand(for item: ResultItem, editor: Editor?) -> EditorCommand? {
        guard case let .line(path, match) = item, let e = editor,
            let appURL = workspace.urlForApplication(withBundleIdentifier: e.bundleId)
        else { return nil }
        return openAtLine(e, appURL: appURL, path: path, line: match.line)
    }

    /// Default app; content hits open at their line in the chosen editor if it is installed.
    static func open(_ item: ResultItem, editor: Editor?) {
        let file = url(item.path)
        if let c = editorCommand(for: item, editor: editor) {
            // The editor's CLI can start and still fail (bad flag, editor gone): fall back to the default app.
            let started = workspace.run(c.executable, c.arguments) { status in
                guard status != 0 else { return }
                Log.actions.error("editor exited with status \(status, privacy: .public); falling back to the default app")
                Task { @MainActor in FileActions.workspace.open(file) }
            }
            if started { return }
            Log.actions.error("editor failed to start; falling back to the default app")
        }
        workspace.open(file)
    }

    /// Shows the file in Finder.
    static func reveal(_ path: String) { workspace.activateFileViewerSelecting([url(path)]) }

    /// Puts the path on the pasteboard as text.
    static func copyPath(_ path: String) {
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    /// Puts the file itself on the pasteboard, so Finder can paste it.
    static func copyFile(_ path: String) {
        pasteboard.clearContents()
        pasteboard.writeObjects([url(path) as NSURL])
    }

    /// Opens the file in a chosen app.
    static func openWith(_ path: String, app: URL) {
        workspace.open([url(path)], withApplicationAt: app, completion: nil)
    }

    /// The folder Terminal opens for a result: itself if a folder, else its parent.
    static func terminalFolder(for path: String) -> String {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue ? path : (path as NSString).deletingLastPathComponent
    }

    /// Opens Terminal in the folder for `path`.
    ///
    /// - Parameters:
    ///   - path: A result's path.
    ///   - onError: Called on the main actor with a message if Terminal is missing or can't open it.
    static func openTerminal(at path: String, onError: @escaping @MainActor (String) -> Void) {
        let folder = terminalFolder(for: path)
        guard let terminal = workspace.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            Log.actions.error("Terminal not found")
            onError("Couldn't find Terminal")
            return
        }
        workspace.open([url(folder)], withApplicationAt: terminal) { error in
            guard let error else { return }
            Log.actions.error("open Terminal failed: \(error.localizedDescription, privacy: .private)")
            let message = "Couldn't open Terminal: \(error.localizedDescription)"
            Task { @MainActor in onError(message) }
        }
    }

    /// Moves the file to the Trash.
    ///
    /// - Throws: The workspace's error, after logging it (privately).
    static func trash(_ path: String) throws {
        do { try workspace.trash(url(path)) } catch {
            Log.actions.error("trash failed: \(error.localizedDescription, privacy: .private)")
            throw error
        }
    }

    /// ⌘Y: show the preview, or close it if it is already up.
    static func quickLook(_ path: String) {
        QuickLookSource.shared.toggle(url(path))
    }
}

/// Feeds the shared Quick Look panel. The launcher panel takes control of it
/// (`acceptsPreviewPanelControl`) and hands it this object as data source.
@MainActor
final class QuickLookSource: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = QuickLookSource()
    /// What the preview shows (or would show, in the unit-test host).
    private(set) var item: URL?
    /// True while the preview is being brought up, before it is visible.
    private(set) var opening = false

    /// Whether Quick Look is up or coming up, so the launcher keeps itself open behind it.
    var isPreviewing: Bool {
        if opening || NSApp.keyWindow is QLPreviewPanel { return true }
        return QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    /// Shows the preview for a file, or closes it if it is already up.
    func toggle(_ u: URL, inert: Bool = Presentation.inert) {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { return close() }
        item = u
        // The unit-test host never brings the preview up: it would take the keyboard.
        guard !inert, let p = QLPreviewPanel.shared() else { return }
        opening = true
        defer { opening = false }
        p.makeKeyAndOrderFront(nil)
        p.reloadData()
    }

    /// Closes the preview if it is up.
    func close() {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { QLPreviewPanel.shared().orderOut(nil) }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { item == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { item as NSURL? }

    /// A local key monitor, held while the preview is attached so it is installed once.
    private var keyMonitor: Any?

    /// The launcher took control of the preview.
    func attach(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        // The preview is key while it is up, so ⌘Y goes to it, not the launcher's key handling: close it here, as ⌘Y toggles.
        keyMonitor =
            keyMonitor
            ?? NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let cmdY =
                    event.modifierFlags.contains(.command)
                    && PanelKey.commandLetter(event.charactersIgnoringModifiers ?? "", shift: event.modifierFlags.contains(.shift)) == .cmdY
                guard cmdY, event.window is QLPreviewPanel else { return event }
                MainActor.assumeIsolated { QuickLookSource.shared.close() }
                return nil
            }
    }

    /// The launcher gave up control of the preview.
    func detach(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }
}
