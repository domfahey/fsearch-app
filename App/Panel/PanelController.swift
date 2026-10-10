import AppKit
import FSearchKit
import KeyboardShortcuts
import SwiftUI

/// The floating launcher: a borderless panel over every Space, centred on
/// the active screen, hidden when it loses focus.
@MainActor
final class PanelController {
    static let shared = PanelController()
    private var panel: NSPanel?
    private var session = PanelSession()
    private weak var app: AppState?

    final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override func resignKey() {
            super.resignKey()
            // UI tests keep the panel up even though the test runner holds focus.
            if !CommandLine.arguments.contains("-UITestShowPanel") {
                MainActor.assumeIsolated { PanelController.shared.hide() }
            }
        }
    }

    func install(app: AppState) {
        self.app = app
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in self?.toggle(app: app) }
        if CommandLine.arguments.contains("-UITestShowPanel") { show(app: app) }
    }

    func toggle(app: AppState) { panel?.isVisible == true ? hide() : show(app: app) }

    func show(app: AppState) {
        self.app = app
        let resumed = session.opened(at: Date())
        app.search.query = resumed.query
        app.search.mode = resumed.mode
        let view = SearchView(model: app.search, state: resumed) { [weak self] effect, items in
            self?.perform(effect, items)
        }.environmentObject(app)
        let p = panel ?? Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: view)
        p.setContentSize(NSSize(width: 680, height: 460))
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.midX - 340, y: f.midY - 30))
        }
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        Task { await app.search.refresh() }
    }

    func hide() {
        guard let p = panel, p.isVisible, let app else { return }
        session.hidden(PanelState(query: app.search.query, mode: app.search.mode), at: Date())
        p.orderOut(nil)
    }

    private func perform(_ effect: PanelEffect, _ items: [ResultItem]) {
        guard let app else { return }
        switch effect {
        case .none: break
        case .hide: hide()
        case let .open(i):
            FileActions.open(items[i], editor: app.editorChoice)
            app.recents.opened(items[i].path)
            hide()
        case let .reveal(i): FileActions.reveal(items[i].path); hide()
        case let .quickLook(i): FileActions.quickLook(items[i].path)
        case let .copyPath(i): FileActions.copyPath(items[i].path)
        case let .showActions(i): ActionsMenu.show(for: items[i], in: panel, app: app)
        }
    }
}
