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

    static func openTerminal(at path: String) {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        let folder = isDir.boolValue ? path : (path as NSString).deletingLastPathComponent
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([url(folder)], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    static func trash(_ path: String) throws {
        try FileManager.default.trashItem(at: url(path), resultingItemURL: nil)
    }

    static func quickLook(_ path: String) {
        QuickLookSource.shared.show(url(path))
    }
}

/// Quick Look needs a data source object kept alive while the panel is up.
@MainActor
final class QuickLookSource: NSObject, @preconcurrency QLPreviewPanelDataSource {
    static let shared = QuickLookSource()
    private var item: URL?
    func show(_ u: URL) {
        item = u
        guard let p = QLPreviewPanel.shared() else { return }
        p.dataSource = self
        p.reloadData()
        p.makeKeyAndOrderFront(nil)
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { 1 }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { item as NSURL? }
}
