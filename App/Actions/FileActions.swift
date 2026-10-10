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

    /// What opens a content hit in the chosen editor, if it is installed: its
    /// open-at-line URL (the file itself for Xcode), handed to that app by
    /// LaunchServices. Never the editor's CLI as our child process, which
    /// would inherit FSearch's Full Disk Access.
    static func editorTarget(for item: ResultItem, editor: Editor?) -> (url: URL, app: URL)? {
        guard case let .line(path, match) = item, let e = editor,
            let appURL = workspace.urlForApplication(withBundleIdentifier: e.bundleId)
        else { return nil }
        return (editorURL(e, path: path, line: match.line) ?? url(path), appURL)
    }

    /// The footer line for a result that is no longer on disk.
    static func missingMessage(_ path: String) -> String {
        "“\((path as NSString).lastPathComponent)” is gone: moved or deleted"
    }

    /// False, after reporting it, if `path` is gone (moved or deleted since the search).
    private static func exists(_ path: String, _ onError: @MainActor (String) -> Void) -> Bool {
        if workspace.fileInfo(atPath: path) != nil { return true }
        Log.actions.error("action on a missing file: \(path, privacy: .private)")
        onError(missingMessage(path))
        return false
    }

    /// Default app; content hits open at their line in the chosen editor if it
    /// is installed. False (reported through `onError`) if the file is gone.
    @discardableResult
    static func open(_ item: ResultItem, editor: Editor?, onError: @escaping @MainActor (String) -> Void) -> Bool {
        guard exists(item.path, onError) else { return false }
        let file = url(item.path)
        guard let target = editorTarget(for: item, editor: editor) else {
            workspace.open(file)
            return true
        }
        // The editor may fail to take the URL (no handler, editor damaged): fall back to the default app.
        workspace.open([target.url], withApplicationAt: target.app) { error in
            guard let error else { return }
            Log.actions.error("editor open failed: \(error.localizedDescription, privacy: .private); falling back to the default app")
            Task { @MainActor in FileActions.workspace.open(file) }
        }
        return true
    }

    /// ↵ reveals, rather than opens, a result that would launch something (an
    /// app, a script, an installer: see `Launchable`). A content hit that the
    /// chosen editor opens runs nothing, so it opens. Only an extensionless
    /// path is looked up on disk.
    static func revealsOnReturn(_ item: ResultItem, editor: Editor?) -> Bool {
        if editorTarget(for: item, editor: editor) != nil { return false }
        let info = Launchable.needsFileCheck(item.path) ? workspace.fileInfo(atPath: item.path) : nil
        return Launchable.revealsOnReturn(
            path: item.path, isDirectory: info?.isDirectory ?? false, isExecutable: info?.isExecutable ?? false)
    }

    /// Shows the file in Finder. False (reported through `onError`) if the file is gone.
    @discardableResult
    static func reveal(_ path: String, onError: @MainActor (String) -> Void) -> Bool {
        guard exists(path, onError) else { return false }
        workspace.activateFileViewerSelecting([url(path)])
        return true
    }

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

    /// Opens the file in a chosen app; a missing file or a launch error goes to `onError`.
    static func openWith(_ path: String, app: URL, onError: @escaping @MainActor (String) -> Void) {
        guard exists(path, onError) else { return }
        let name = app.deletingPathExtension().lastPathComponent
        workspace.open([url(path)], withApplicationAt: app) { error in
            guard let error else { return }
            Log.actions.error("Open With failed: \(error.localizedDescription, privacy: .private)")
            let message = "Couldn't open with \(name): \(error.localizedDescription)"
            Task { @MainActor in onError(message) }
        }
    }

    /// The folder Terminal opens for a result: itself if a plain folder, else
    /// its parent. A package (an app, an .rtfd) is a file here: never its insides.
    static func terminalFolder(for path: String) -> String {
        let info = workspace.fileInfo(atPath: path)
        return info?.isDirectory == true && info?.isPackage == false ? path : (path as NSString).deletingLastPathComponent
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
                // By key code too: on a non-Latin layout ⌘Y types "н".
                let letter = PanelKey.commandLetter(
                    event.charactersIgnoringModifiers ?? "", shift: event.modifierFlags.contains(.shift), keyCode: event.keyCode)
                let cmdY = event.modifierFlags.contains(.command) && letter == .cmdY
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
