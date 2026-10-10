import AppKit
import FSearchKit
import KeyboardShortcuts
import Quartz
import SwiftUI

/// The floating launcher: a borderless panel over every Space, centred on
/// the active screen, hidden when it loses focus.
@MainActor
final class PanelController: PanelHost {
    static let shared = PanelController()
    private(set) var panel: NSPanel?
    private var session = PanelSession()
    private weak var app: AppState?
    private(set) var selection = 0
    /// The app that was in front when the panel opened, to hand focus back to.
    private var previousApp: NSRunningApplication?

    final class Panel: NSPanel {
        /// The unit-test host's panel must never take the keyboard from the user.
        override var canBecomeKey: Bool { !LaunchOptions.current.unitTestHost }
        override func resignKey() {
            super.resignKey()
            // UI tests keep the panel up even though the test runner holds focus.
            if LaunchOptions.current.showPanel { return }
            // Quick Look takes key while it previews; the launcher stays up behind it.
            if QuickLookSource.shared.isPreviewing { return }
            // The user moved to another app, so don't pull focus back.
            PanelController.shared.hide(returnFocus: false)
        }

        // Quick Look looks for a controller up the key window's responder chain.
        override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
        override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
            MainActor.assumeIsolated { QuickLookSource.shared.attach(panel) }
        }
        override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
            MainActor.assumeIsolated { QuickLookSource.shared.detach(panel) }
            // The preview closed: give the keyboard back to the launcher.
            DispatchQueue.main.async {
                guard self.isVisible else { return }
                if NSApp.isActive { self.makeKey() } else { PanelController.shared.hide(returnFocus: false) }
            }
        }
    }

    /// A test-mode app (UI tests) must not take the user's own global shortcut.
    static func registersGlobalHotkey(_ options: LaunchOptions) -> Bool { !options.testMode }

    func install(app: AppState) {
        self.app = app
        if Self.registersGlobalHotkey(app.options) {
            KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in self?.toggle(app: app) }
        }
        if LaunchOptions.current.showPanel { show(app: app) }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func toggle(app: AppState) { panel?.isVisible == true ? hide() : show(app: app) }

    func show(app: AppState) {
        self.app = app
        let resumed = session.opened(at: Date())
        app.search.query = resumed.query
        app.search.mode = resumed.mode
        selection = resumed.selection
        let view = SearchView(
            model: app.search, state: resumed,
            onEffect: { [weak self] effect, items in
                self?.perform(effect, items)
            }, onSelect: { [weak self] in self?.selection = $0 },
            onCommand: { [weak self] in self?.run($0) }
        ).environmentObject(app)
        let p = panel ?? Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: view)
        let size = NSSize(width: 680, height: 460)
        p.setContentSize(size)
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            p.setFrameOrigin(PanelFrame.origin(size: size, in: screen.visibleFrame))
        }
        panel = p
        let front = NSWorkspace.shared.frontmostApplication
        previousApp = front == NSRunningApplication.current ? nil : front
        AppActivation.activate()
        Self.present(p)
        Task { await app.search.refresh() }
    }

    /// Puts the panel on screen and makes it key. The inert unit-test host only
    /// orders it in, fully transparent and deaf to the mouse, and never key.
    static func present(_ p: NSPanel, inert: Bool = Presentation.inert) {
        Presentation.present(p, inert: inert)
    }

    /// `returnFocus` is false when hiding because the user clicked another app.
    func hide(returnFocus: Bool = true) {
        guard let p = panel, p.isVisible, let app else { return }
        session.hidden(PanelState(query: app.search.query, mode: app.search.mode, selection: selection), at: Date())
        p.orderOut(nil)
        QuickLookSource.shared.close()
        // The unit-test host never moves focus between apps.
        guard returnFocus && !Presentation.inert && NSApp.isActive else { return }
        // Hiding the app hands focus back to whatever was in front before, but it
        // would hide Settings, onboarding or a debug window too. With one of those
        // up, give focus straight to the app the panel was summoned over (if it
        // was another app and is still running); our windows stay where they were.
        if Self.otherWindowsVisible(except: p) {
            if let prev = previousApp, !prev.isTerminated { prev.activate() }
        } else {
            NSApp.hide(nil)
        }
        previousApp = nil
    }

    /// A regular window of ours is on screen: titled, not a panel (the launcher,
    /// Quick Look) and not the menu-bar item's borderless window.
    private static func otherWindowsVisible(except panel: NSWindow) -> Bool {
        NSApp.windows.contains { w in
            w !== panel && w.isVisible && !(w is NSPanel) && w.styleMask.contains(.titled)
        }
    }

    /// Opens Settings, the same window the menu's SettingsLink opens. Never in
    /// the unit-test host: the window would come up over the user's apps.
    static var openSettings: () -> Void = { openSettingsWindow() }

    /// macOS 14+ only logs "Please use SettingsLink" for `showSettingsWindow:`,
    /// so this performs the app menu's Settings… item (⌘,), which SwiftUI's
    /// Settings scene adds to the (hidden) main menu even for a menu-bar app.
    /// Does nothing, and returns false, in the inert unit-test host.
    @discardableResult
    static func openSettingsWindow(inert: Bool = Presentation.inert, menu: @autoclosure () -> NSMenu? = NSApp.mainMenu) -> Bool {
        guard !inert else { return false }
        AppActivation.activate()
        if performSettingsMenuItem(in: menu()) { return true }
        Log.actions.error("Settings: no ⌘, item in the main menu")
        return false
    }

    /// Performs the first item bound to plain ⌘, in `menu` or its submenus.
    static func performSettingsMenuItem(in menu: NSMenu?) -> Bool {
        guard let (owner, index) = settingsItem(in: menu) else { return false }
        owner.performActionForItem(at: index)
        return true
    }

    private static func settingsItem(in menu: NSMenu?) -> (NSMenu, Int)? {
        guard let menu else { return nil }
        for (i, item) in menu.items.enumerated() {
            if item.keyEquivalent == "," && item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask) == .command {
                return (menu, i)
            }
            if let found = settingsItem(in: item.submenu) { return found }
        }
        return nil
    }

    /// Runs an app command from its panel row and puts the launcher away.
    func run(_ command: AppCommand) {
        switch command {
        case .settings: Self.openSettings()
        }
        hide(returnFocus: false)
    }

    func perform(_ effect: PanelEffect, _ items: [ResultItem]) {
        guard let app else { return }
        switch effect {
        case let .open(i), let .reveal(i), let .quickLook(i), let .copyPath(i), let .showActions(i):
            guard items.indices.contains(i) else { return }
        case .none, .hide: break
        }
        let errors = app.actionErrorCount
        switch effect {
        case .none: break
        case .hide: hide()
        case let .open(i):
            // ↵ on an app, script or installer reveals it; ⌘K → Open launches it.
            if FileActions.revealsOnReturn(items[i], editor: app.editor) {
                FileActions.reveal(items[i].path, onError: app.showActionError)
            } else if FileActions.open(items[i], editor: app.editor, onError: app.showActionError) {
                app.openedRecent(items[i].path)
            }
        case let .reveal(i): FileActions.reveal(items[i].path, onError: app.showActionError)
        case let .quickLook(i): FileActions.quickLook(items[i].path)
        case let .copyPath(i): FileActions.copyPath(items[i].path)
        case let .showActions(i): ActionsMenu.show(for: items[i], in: panel, app: app)
        }
        // The same rule as the ⌘K menu: going to another app puts the launcher
        // away, unless the action failed at once and its error needs reading.
        if PanelInput.menuAction(for: effect)?.hidesPanel(errored: app.actionErrorCount != errors) == true { hide() }
    }
}
