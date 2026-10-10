import AppKit
import FSearchKit

/// The ⌘K menu of actions for a result.
@MainActor
enum ActionsMenu {
    /// Pops the menu up near the panel's lower right.
    static func show(for item: ResultItem, in panel: NSPanel?, app: AppState) {
        let menu = build(for: item, app: app)
        guard let view = panel?.contentView else { return }
        popUp(menu, NSPoint(x: view.bounds.maxX - 220, y: 40), view)
    }

    /// Shows the menu (modal, on screen). Never in the unit-test host; tests
    /// may replace it to see what would have been shown.
    static var popUp: @MainActor (NSMenu, NSPoint, NSView) -> Void = { menu, at, view in
        guard !Presentation.inert else { return }
        menu.popUp(positioning: nil, at: at, in: view)
    }

    /// ⌘K's menu for one result. Each item runs its action through `Target`.
    static func build(for item: ResultItem, app: AppState) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let path = item.path
        func entry(_ title: String, _ kind: MenuAction, _ action: @escaping @MainActor () -> Void) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: #selector(Target.run(_:)), keyEquivalent: "")
            let t = Target {
                let errors = app.actionErrorCount
                action()
                if kind.recordsRecent { app.openedRecent(path) }
                // Like ↵: the user went to another app, so the launcher goes away,
                // unless the action already failed and its error line needs reading.
                if kind.hidesPanel(errored: app.actionErrorCount != errors) { app.panel.hide(returnFocus: true) }
            }
            i.target = t
            i.representedObject = t  // the item keeps its target alive
            return i
        }
        menu.addItem(entry("Open", .open) { FileActions.open(item, editor: app.editor) })
        let with = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        // Capped at 12 so the submenu stays short.
        let apps = FileActions.workspace.urlsForApplications(toOpen: FileActions.url(path)).prefix(12)
        if apps.isEmpty {
            with.isEnabled = false
        } else {
            let sub = NSMenu()
            for appURL in apps {
                sub.addItem(
                    entry(FileManager.default.displayName(atPath: appURL.path), .openWith) { FileActions.openWith(path, app: appURL) })
            }
            with.submenu = sub
        }
        menu.addItem(with)
        menu.addItem(entry("Reveal in Finder", .reveal) { FileActions.reveal(path) })
        menu.addItem(entry("Quick Look", .quickLook) { FileActions.quickLook(path) })
        menu.addItem(entry("Copy Path", .copyPath) { FileActions.copyPath(path) })
        menu.addItem(entry("Copy File", .copyFile) { FileActions.copyFile(path) })
        menu.addItem(
            entry("Open Folder in Terminal", .openTerminal) {
                FileActions.openTerminal(at: path) { app.showActionError($0) }
            })
        menu.addItem(.separator())
        menu.addItem(
            entry("Move to Trash", .trash) {
                do {
                    try FileActions.trash(path)
                    app.recentsChanged()  // an empty query shows Recents: drop the trashed row
                    Task { await app.search.refresh() }
                } catch {
                    app.showActionError("Couldn't move to Trash: \(error.localizedDescription)")
                }
            })
        return menu
    }

    /// Carries a menu item's action closure, which `NSMenuItem` can only reach through an Objective-C selector.
    final class Target: NSObject {
        let action: @MainActor () -> Void
        init(_ a: @escaping @MainActor () -> Void) { action = a }
        @MainActor @objc func run(_ sender: Any?) { action() }
    }
}
