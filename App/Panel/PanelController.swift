import AppKit
import FSearchKit
import KeyboardShortcuts
import Quartz
import SwiftUI

/// The floating launcher: a borderless panel over every Space, centred on
/// the active screen, hidden when it loses focus.
///
/// Focus: the panel is non-activating, and ``show(app:)`` remembers the app that was in front
/// (``hide(returnFocus:)`` hands focus back to it). Clicking another app hides the panel without
/// returning focus, since the user already chose where it goes.
///
/// Inert host: in the unit-test host (``Presentation/inert``) the panel is ordered in invisibly,
/// can't become key, and never activates the app or moves focus, so tests never disturb the user.
@MainActor
final class PanelController: PanelHost {
    static let shared = PanelController()
    /// The panel, created on the first `show`.
    private(set) var panel: Panel?
    /// The app whose `SearchView` is currently hosted in `panel.contentView`.
    private weak var hostedApp: AppState?
    /// Observable state box shared with the hosted `SearchView` so `show()` reuses the view hierarchy.
    private(set) var viewState = PanelViewState()
    /// Remembers the state at hide, so a quick reopen resumes.
    private var session = PanelSession()
    private weak var app: AppState?
    /// Observer that hides the panel when the user switches to another app (even if Quick Look held key).
    private var resignActiveObserver: ObserverToken?
    /// The selected row, mirrored from the view so ``hide(returnFocus:)`` can save it.
    private(set) var selection = 0
    /// The app that was in front when the panel opened, to hand focus back to.
    private var previousApp: NSRunningApplication?
    /// A result key waiting for results; hiding drops it, so it never runs behind the user's back.
    let held = HeldKeyBox()
    /// Keys sent to the view from outside it: ↑/↓ in Quick Look.
    let keys = PanelKeyFeed()
    /// Where the view laid out its rows, so ⌘K's menu opens at the selected one.
    let geometry = PanelGeometry()
    /// The FSearch menu (⌘/); hiding the panel closes it, and opening it drops the held key.
    private(set) lazy var menu = AppMenuState(held: held)

    /// The panel window: key only outside the unit-test host, hides on resign, and hosts the Quick Look controller.
    final class Panel: NSPanel {
        /// The unit-test host's panel must never take the keyboard from the user.
        override var canBecomeKey: Bool { !LaunchOptions.current.unitTestHost }
        /// The app's `showPanel` option: UI tests keep the panel up even though the test runner holds focus.
        var staysUpWithoutKey = false
        override func resignKey() {
            super.resignKey()
            if staysUpWithoutKey { return }
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
            DispatchQueue.main.async { self.restoreFocusAfterPreview() }
        }

        /// Restores keyboard focus to the panel if FSearch is still active, or hides it otherwise.
        func restoreFocusAfterPreview(
            isActive: Bool = NSApp.isActive, keyWindow: NSWindow? = NSApp.keyWindow,
            makeKey: (() -> Void)? = nil, hide: (() -> Void)? = nil
        ) {
            guard isVisible else { return }
            if isActive && (keyWindow == nil || keyWindow === self) {
                if let makeKey { makeKey() } else { self.makeKey() }
            } else {
                if let hide { hide() } else { PanelController.shared.hide(returnFocus: false) }
            }
        }
    }

    /// A test-mode app (UI tests) must not take the user's own global shortcut.
    static func registersGlobalHotkey(_ options: LaunchOptions) -> Bool { !options.testMode }

    /// Connects the panel to the app and registers the global shortcut (not in test mode).
    func install(app: AppState, registerHotkey: ((@escaping @MainActor () -> Void) -> Void)? = nil) {
        self.app = app
        if Self.registersGlobalHotkey(app.options) {
            let toggle: @MainActor () -> Void = { [weak self] in self?.toggle(app: app) }
            if let registerHotkey {
                registerHotkey(toggle)
            } else {
                KeyboardShortcuts.onKeyUp(for: .togglePanel, action: toggle)
            }
        }
        if app.options.showPanel { show(app: app) }
    }

    var isVisible: Bool { panel?.isVisible == true }

    /// The shortcut and the menu's "Search…": show the panel, or hide it if it is up.
    func toggle(app: AppState) { panel?.isVisible == true ? hide() : show(app: app) }

    /// Shows the panel on the screen holding the mouse, resuming the last query if it was hidden within the resume window.
    func show(app: AppState) {
        present(app: app, state: session.opened(at: Date()))
    }

    /// Shows the panel pre-filled with a parsed `fsearch://` search, replacing any resumed session state.
    func show(app: AppState, search: SearchURL) {
        present(app: app, state: PanelState(query: search.query, mode: search.mode, selection: 0))
    }

    /// Parses and opens a `fsearch://` URL in the panel. Returns false for unrecognized URLs without showing the panel.
    @discardableResult
    func open(url: URL, app: AppState) -> Bool {
        guard let search = SearchURL.parse(url) else { return false }
        show(app: app, search: search)
        return true
    }

    private func present(app: AppState, state: PanelState) {
        let wasVisible = isVisible
        self.app = app
        observeAppResignActive()
        app.recents.invalidate()
        app.search.query = state.query
        app.search.mode = state.mode
        selection = state.selection
        viewState.resume(state)
        held.key.cancel()
        menu.close()
        let p = panel ?? Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.staysUpWithoutKey = app.options.showPanel
        p.isFloatingPanel = true
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if p.contentView == nil || hostedApp !== app {
            geometry.rows = [:]
            let view = SearchView(
                model: app.search, viewState: viewState, held: held, keys: keys, geometry: geometry, menu: menu,
                isVisible: { [weak self] in self?.isVisible == true },
                onEffect: { [weak self] effect, items in
                    self?.perform(effect, items)
                }, onSelect: { [weak self] in self?.selection = $0 },
                onCommand: { [weak self] in self?.run($0) }
            ).environmentObject(app)
            p.contentView = NSHostingView(rootView: view)
            hostedApp = app
        }
        // 680 x 460 matches SearchView's frame; PanelFrame centres it horizontally, a little above the middle, inside the visible frame.
        let size = NSSize(width: 680, height: 460)
        p.setContentSize(size)
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            p.setFrameOrigin(PanelFrame.origin(size: size, in: screen.visibleFrame))
        }
        panel = p
        updatePreviousApp(front: NSWorkspace.shared.frontmostApplication, wasVisible: wasVisible)
        AppActivation.activate()
        Presentation.present(p)
        viewState.requestFocus()
        Task { await app.search.refresh() }
    }

    /// Remembers the frontmost non-FSearch app, or clears it when opening fresh while FSearch is already frontmost.
    func updatePreviousApp(
        front: NSRunningApplication?, current: NSRunningApplication = .current, wasVisible: Bool
    ) {
        if front != current {
            previousApp = front
        } else if !wasVisible {
            previousApp = nil
        }
    }

    /// Hides the panel when the user switches to another app, even while Quick Look held key.
    private func observeAppResignActive() {
        guard resignActiveObserver == nil else { return }
        let token = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisible, self.panel?.staysUpWithoutKey == false else { return }
                self.hide(returnFocus: false)
            }
        }
        resignActiveObserver = ObserverToken(center: .default, token: token)
    }

    /// Hides the panel, saving its state for a quick reopen.
    ///
    /// - Parameter returnFocus: False when hiding because the user clicked another app, so focus isn't pulled back.
    func hide(returnFocus: Bool = true) {
        held.key.cancel()
        menu.close()
        guard let p = panel, p.isVisible, let app else { return }
        defer { previousApp = nil }
        session.hidden(PanelState(query: app.search.query, mode: app.search.mode, selection: selection), at: Date())
        p.orderOut(nil)
        QuickLookSource.shared.close()
        restoreFocusOnHide(except: p, returnFocus: returnFocus)
    }

    /// Returns focus after hiding the panel: activates the previous app if another window of ours stays open, or hides the app.
    func restoreFocusOnHide(
        except panel: NSWindow, returnFocus: Bool, inert: Bool = Presentation.inert,
        appIsActive: Bool = NSApp.isActive, windows: [NSWindow] = NSApp.windows,
        activate: ((NSRunningApplication) -> Void)? = nil, hideApp: (() -> Void)? = nil
    ) {
        // The unit-test host never moves focus between apps.
        guard returnFocus && !inert && appIsActive else { return }
        // Hiding the app hands focus back to whatever was in front before, but it
        // would hide Settings, onboarding or a debug window too. With one of those
        // up, give focus straight to the app the panel was summoned over (if it
        // was another app and is still running); our windows stay where they were.
        if Self.otherWindowsVisible(except: panel, in: windows) {
            if let prev = previousApp, !prev.isTerminated {
                if let activate { activate(prev) } else { prev.activate() }
            }
        } else {
            if let hideApp { hideApp() } else { NSApp.hide(nil) }
        }
    }

    /// A regular window of ours is on screen: titled, not a panel (the launcher,
    /// Quick Look) and not the menu-bar item's borderless window.
    static func otherWindowsVisible(except panel: NSWindow, in windows: [NSWindow] = NSApp.windows) -> Bool {
        windows.contains { w in
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

    /// Carries out a panel key's effect on the results.
    ///
    /// - Parameters:
    ///   - effect: What ``PanelState/reduce(_:)`` asked for; indices are file indices.
    ///   - items: The results showing; an index outside them is ignored.
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
        case let .quickLook(i): FileActions.quickLook(items[i].path, onError: app.showActionError)
        case let .copyPath(i): FileActions.copyPath(items[i].path)
        case let .showActions(i): ActionsMenu.show(for: items[i], in: panel, app: app, geometry: geometry)
        }
        // The same rule as the ⌘K menu: going to another app puts the launcher
        // away, unless the action failed at once and its error needs reading.
        if PanelInput.menuAction(for: effect)?.hidesPanel(errored: app.actionErrorCount != errors) == true { hide() }
    }
}

/// Removes a `NotificationCenter` observer automatically on deallocation.
private final class ObserverToken {
    let center: NotificationCenter
    let token: NSObjectProtocol
    init(center: NotificationCenter, token: NSObjectProtocol) { (self.center, self.token) = (center, token) }
    deinit { center.removeObserver(token) }
}
