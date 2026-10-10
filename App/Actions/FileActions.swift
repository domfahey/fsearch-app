import AppKit
import FSearchKit
import Quartz

@MainActor
enum FileActions {
    static func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    /// Default app; content hits open at their line in the chosen editor if it is installed.
    static func open(_ item: ResultItem, editor: Editor?) {
        if case let .line(path, match) = item, let e = editor,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: e.bundleId) {
            let c = openAtLine(e, appURL: appURL, path: path, line: match.line)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: c.executable)
            p.arguments = c.arguments
            // The editor's CLI can start and still fail (bad flag, editor gone): fall back to the default app.
            let file = url(item.path)
            p.terminationHandler = { proc in
                guard proc.terminationStatus != 0 else { return }
                Task { @MainActor in NSWorkspace.shared.open(file) }
            }
            if (try? p.run()) != nil { return }
        }
        NSWorkspace.shared.open(url(item.path))
    }

    static func reveal(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([url(path)]) }

    static func copyPath(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    static func copyFile(_ path: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url(path) as NSURL])
    }

    static func openWith(_ path: String, app: URL) {
        NSWorkspace.shared.open([url(path)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static func openTerminal(at path: String, onError: @escaping @MainActor (String) -> Void) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        let folder = isDir.boolValue ? path : (path as NSString).deletingLastPathComponent
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            onError("Couldn't find Terminal")
            return
        }
        NSWorkspace.shared.open([url(folder)], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            let message = "Couldn't open Terminal: \(error.localizedDescription)"
            Task { @MainActor in onError(message) }
        }
    }

    static func trash(_ path: String) throws {
        try FileManager.default.trashItem(at: url(path), resultingItemURL: nil)
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
