import AppKit
import FSearchKit

/// The ⌘K menu of actions for a result.
@MainActor
enum ActionsMenu {
    /// Pops the menu up under the result's row, or under the search field if the row is out of view.
    static func show(for item: ResultItem, in panel: NSPanel?, app: AppState, geometry: PanelGeometry = PanelGeometry()) {
        let menu = build(for: item, app: app)
        guard let view = panel?.contentView else { return }
        popUp(menu, PanelGeometry.viewPoint(geometry.menuAnchor(rowID: item.id), in: view), view)
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
                let errored = app.actionErrorCount != errors
                // A file that turned out to be gone is not a recent.
                if kind.recordsRecent && !errored { app.openedRecent(path) }
                // Like ↵: the user went to another app, so the launcher goes away,
                // unless the action already failed and its error line needs reading.
                if kind.hidesPanel(errored: errored) { app.panel.hide(returnFocus: true) }
            }
            i.target = t
            i.representedObject = t  // the item keeps its target alive
            return i
        }
        menu.addItem(entry("Open", .open) { FileActions.open(item, editor: app.editor, onError: app.showActionError) })
        let with = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        // Capped at 12 so the submenu stays short.
        let apps = FileActions.workspace.urlsForApplications(toOpen: FileActions.url(path)).prefix(12)
        if apps.isEmpty {
            with.isEnabled = false
        } else {
            let sub = NSMenu()
            for appURL in apps {
                sub.addItem(
                    entry(FileManager.default.displayName(atPath: appURL.path), .openWith) {
                        FileActions.openWith(path, app: appURL, onError: app.showActionError)
                    })
            }
            with.submenu = sub
        }
        menu.addItem(with)
        menu.addItem(entry("Reveal in Finder", .reveal) { FileActions.reveal(path, onError: app.showActionError) })
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

/// Where the panel's rows, list and search field are, from the panel's top
/// left, as the view last laid them out; ⌘K's menu opens from here.
@MainActor
final class PanelGeometry {
    /// The coordinate space the frames are in: the panel's whole view.
    nonisolated static let space = "panel"
    /// The menu's left edge sits this far in from a row's, under its name.
    nonisolated static let inset: CGFloat = 44

    /// Row frames by row id (``PanelInput/rowID(at:shown:rows:)``).
    var rows: [String: CGRect] = [:]
    /// The scrolling list's frame: rows outside it are out of view.
    var list: CGRect = .zero
    /// The search field's row; the menu opens under it when no row is in view.
    var field = CGRect(x: 0, y: 0, width: 680, height: 50)

    /// New rows arrived: keep the frames of rows still shown (one that didn't
    /// move never reports again) and drop the rest, so `rows` stays small.
    func rowsChanged(keeping ids: Set<String>) {
        rows = rows.filter { ids.contains($0.key) }
    }

    /// Where the menu for a row opens, from the panel's top left.
    func menuAnchor(rowID: String) -> CGPoint {
        Self.menuAnchor(row: rows[rowID], list: list, field: field)
    }

    /// Under the row if any of it is in the list's view (no lower than the
    /// list's bottom), else under the search field.
    nonisolated static func menuAnchor(row: CGRect?, list: CGRect, field: CGRect) -> CGPoint {
        guard let row, row.intersects(list) else { return CGPoint(x: field.minX + inset, y: field.maxY) }
        return CGPoint(x: row.minX + inset, y: min(row.maxY, list.maxY))
    }

    /// A point from the top left in `view`'s own coordinates, which count from
    /// the bottom unless the view is flipped.
    static func viewPoint(_ p: CGPoint, in view: NSView) -> NSPoint {
        view.isFlipped ? p : NSPoint(x: p.x, y: view.bounds.height - p.y)
    }
}
