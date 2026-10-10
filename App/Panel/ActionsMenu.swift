import AppKit
import FSearchKit

@MainActor
enum ActionsMenu {
    static func show(for item: ResultItem, in panel: NSPanel?, app: AppState) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let path = item.path
        func entry(_ title: String, _ kind: MenuAction, _ action: @escaping @MainActor () -> Void) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: #selector(Target.run(_:)), keyEquivalent: "")
            let t = Target {
                action()
                if kind.recordsRecent { app.recents.opened(path) }
                // Like ↵: the user went to another app, so the launcher goes away.
                if kind.hidesPanel { PanelController.shared.hide() }
            }
            i.target = t
            i.representedObject = t  // the item keeps its target alive
            return i
        }
        menu.addItem(entry("Open", .open) { FileActions.open(item, editor: app.editor) })
        let with = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: FileActions.url(path)).prefix(12)
        if apps.isEmpty {
            with.isEnabled = false
        } else {
            let sub = NSMenu()
            for appURL in apps {
                sub.addItem(entry(FileManager.default.displayName(atPath: appURL.path), .openWith) { FileActions.openWith(path, app: appURL) })
            }
            with.submenu = sub
        }
        menu.addItem(with)
        menu.addItem(entry("Reveal in Finder", .reveal) { FileActions.reveal(path) })
        menu.addItem(entry("Quick Look", .quickLook) { FileActions.quickLook(path) })
        menu.addItem(entry("Copy Path", .copyPath) { FileActions.copyPath(path) })
        menu.addItem(entry("Copy File", .copyFile) { FileActions.copyFile(path) })
        menu.addItem(entry("Open Folder in Terminal", .openTerminal) {
            FileActions.openTerminal(at: path) { app.showActionError($0) }
        })
        menu.addItem(.separator())
        menu.addItem(entry("Move to Trash", .trash) {
            do {
                try FileActions.trash(path)
                Task { await app.search.refresh() }
            } catch {
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
