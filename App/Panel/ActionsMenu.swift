import AppKit
import FSearchKit

@MainActor
enum ActionsMenu {
    static func show(for item: ResultItem, in panel: NSPanel?, app: AppState) {
        let menu = NSMenu()
        func entry(_ title: String, _ action: @escaping @MainActor () -> Void) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: #selector(Target.run(_:)), keyEquivalent: "")
            let t = Target(action)
            i.target = t
            i.representedObject = t  // the item keeps its target alive
            return i
        }
        let path = item.path
        menu.addItem(entry("Open") {
            FileActions.open(item, editor: app.editor)
            app.recents.opened(path)
        })
        let with = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for appURL in NSWorkspace.shared.urlsForApplications(toOpen: FileActions.url(path)).prefix(12) {
            sub.addItem(entry(FileManager.default.displayName(atPath: appURL.path)) { FileActions.openWith(path, app: appURL) })
        }
        with.submenu = sub
        menu.addItem(with)
        menu.addItem(entry("Reveal in Finder") { FileActions.reveal(path) })
        menu.addItem(entry("Quick Look") { FileActions.quickLook(path) })
        menu.addItem(entry("Copy Path") { FileActions.copyPath(path) })
        menu.addItem(entry("Copy File") { FileActions.copyFile(path) })
        menu.addItem(entry("Open Folder in Terminal") { FileActions.openTerminal(at: path) })
        menu.addItem(.separator())
        menu.addItem(entry("Move to Trash") {
            do { try FileActions.trash(path) } catch {
                app.showActionError("Couldn't move to Trash: \(error.localizedDescription)")
            }
        })
        guard let view = panel?.contentView else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: view.bounds.maxX - 220, y: 40), in: view)
    }

    final class Target: NSObject {
        let action: @MainActor () -> Void
        init(_ a: @escaping @MainActor () -> Void) { action = a }
        @MainActor @objc func run(_ sender: Any?) { action() }
    }
}
