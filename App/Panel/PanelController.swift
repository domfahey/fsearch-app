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
    private var selection = 0

    final class Panel: NSPanel {
        override var canBecomeKey: Bool { true }
        override func resignKey() {
            super.resignKey()
            // UI tests keep the panel up even though the test runner holds focus.
            // The user moved to another app, so don't pull focus back.
            if !CommandLine.arguments.contains("-UITestShowPanel") {
                MainActor.assumeIsolated { PanelController.shared.hide(returnFocus: false) }
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
        selection = resumed.selection
        let view = SearchView(model: app.search, state: resumed, onEffect: { [weak self] effect, items in
            self?.perform(effect, items)
        }, onSelect: { [weak self] in self?.selection = $0 }).environmentObject(app)
        let p = panel ?? Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: view)
        p.setContentSize(NSSize(width: 680, height: 460))
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.midX - 340, y: f.midY - 30 + f.height / 6))
        }
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        Task { await app.search.refresh() }
    }

    /// `returnFocus` is false when hiding because the user clicked another app.
    func hide(returnFocus: Bool = true) {
        guard let p = panel, p.isVisible, let app else { return }
        session.hidden(PanelState(query: app.search.query, mode: app.search.mode, selection: selection), at: Date())
        p.orderOut(nil)
        // Hiding the app hands focus back to whatever was in front before.
        if returnFocus && NSApp.isActive { NSApp.hide(nil) }
    }

    private func perform(_ effect: PanelEffect, _ items: [ResultItem]) {
        guard let app else { return }
        switch effect {
        case let .open(i), let .reveal(i), let .quickLook(i), let .copyPath(i), let .showActions(i):
            guard items.indices.contains(i) else { return }
        case .none, .hide: break
        }
        switch effect {
        case .none: break
        case .hide: hide()
        case let .open(i):
            FileActions.open(items[i], editor: app.editor)
            app.recents.opened(items[i].path)
            hide()
        case let .reveal(i): FileActions.reveal(items[i].path); hide()
        case let .quickLook(i): FileActions.quickLook(items[i].path)
        case let .copyPath(i): FileActions.copyPath(items[i].path)
        case let .showActions(i): ActionsMenu.show(for: items[i], in: panel, app: app)
        }
    }
}
