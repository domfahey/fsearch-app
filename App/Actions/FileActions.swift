import AppKit
import FSearchKit
import os
import Quartz

@MainActor
enum FileActions {
    /// Where actions go: the real workspace, or a fake under test.
    static var workspace: Workspace = SystemWorkspace()
    /// ⌘⇧C and "Copy File" write here: the general pasteboard, or a private one under test.
    static var pasteboard: NSPasteboard = .general

    static func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    /// The editor command for a content hit, if an editor is chosen and installed.
    static func editorCommand(for item: ResultItem, editor: Editor?) -> EditorCommand? {
        guard case let .line(path, match) = item, let e = editor,
              let appURL = workspace.urlForApplication(withBundleIdentifier: e.bundleId) else { return nil }
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

    static func reveal(_ path: String) { workspace.activateFileViewerSelecting([url(path)]) }

    static func copyPath(_ path: String) {
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }

    static func copyFile(_ path: String) {
        pasteboard.clearContents()
        pasteboard.writeObjects([url(path) as NSURL])
    }

    static func openWith(_ path: String, app: URL) {
        workspace.open([url(path)], withApplicationAt: app, completion: nil)
    }

    /// The folder Terminal opens for a result: itself if a folder, else its parent.
    static func terminalFolder(for path: String) -> String {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue ? path : (path as NSString).deletingLastPathComponent
    }

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
    private var item: URL?
    /// True while the preview is being brought up, before it is visible.
    private(set) var opening = false

    /// Whether Quick Look is up or coming up, so the launcher keeps itself open behind it.
    var isPreviewing: Bool {
        if opening || NSApp.keyWindow is QLPreviewPanel { return true }
        return QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
    }

    func toggle(_ u: URL) {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { return close() }
        item = u
        guard let p = QLPreviewPanel.shared() else { return }
        opening = true
        defer { opening = false }
        p.makeKeyAndOrderFront(nil)
        p.reloadData()
    }

    func close() {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { QLPreviewPanel.shared().orderOut(nil) }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { item == nil ? 0 : 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { item as NSURL? }

    private var keyMonitor: Any?

    /// The launcher took control of the preview.
    func attach(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        // The preview is key while it is up, so ⌘Y lands on it: close it, as ⌘Y toggles.
        keyMonitor = keyMonitor ?? NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let cmdY = event.modifierFlags.contains(.command)
                && PanelKey.commandLetter(event.charactersIgnoringModifiers ?? "", shift: event.modifierFlags.contains(.shift)) == .cmdY
            guard cmdY, event.window is QLPreviewPanel else { return event }
            MainActor.assumeIsolated { QuickLookSource.shared.close() }
            return nil
        }
    }

    func detach(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }
}
