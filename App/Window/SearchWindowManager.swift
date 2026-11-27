import AppKit
import FSearchKit
import Quartz
import SwiftUI

/// Manages one or more independent Everything-style search windows alongside the floating panel.
@MainActor
final class SearchWindowManager {
    /// Shared window manager used by menu actions and commands.
    static let shared = SearchWindowManager()

    /// Entry-point seam so tests can intercept opening a search window without showing one.
    static var open: @MainActor (AppState, String) -> Void = { app, query in
        _ = SearchWindowManager.shared.openWindow(app: app, initialQuery: query)
    }

    /// Entry-point that preserves non-default search modes (Inside Files / Definitions) when carrying over from the panel.
    static var openWithMode: @MainActor (AppState, String, SearchMode) -> Void = { app, query, mode in
        if mode == .names {
            open(app, query)
        } else {
            _ = SearchWindowManager.shared.openWindow(app: app, initialQuery: query, initialMode: mode)
        }
    }

    /// Open windows keyed by identifier; cleaned up automatically on close.
    private(set) var windows: [UUID: NSWindow] = [:]
    private var windowOrder: [UUID] = []
    private var observers: [UUID: [NSObjectProtocol]] = [:]
    private var cascadePoint = NSPoint.zero

    /// Number of currently open search windows.
    var openCount: Int { windows.count }

    /// Computes the window title from the current search query.
    static func windowTitle(for query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "FSearch") : "FSearch — \(DisplaySafe.name(trimmed))"
    }

    /// Creates an `NSWindow` configured for a search browser (inert non-key window in unit tests).
    static func makeWindow(size: NSSize = NSSize(width: 1080, height: 680), inert: Bool = Presentation.inert) -> SearchBrowserWindow {
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let origin = inert ? NSPoint(x: -20_000, y: -20_000) : .zero
        let window: SearchBrowserWindow =
            inert
            ? InertSearchWindow(contentRect: NSRect(origin: origin, size: size), styleMask: style, backing: .buffered, defer: false)
            : SearchBrowserWindow(contentRect: NSRect(origin: origin, size: size), styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 480)
        return window
    }

    /// Creates and presents a new independent search window.
    ///
    /// - Parameters:
    ///   - app: Shared app state (used to create independent window backends, saved-search store, and Recents).
    ///   - initialQuery: Optional starting query carried over from the panel.
    ///   - initialMode: Optional starting search mode.
    ///   - inert: When true (unit-test host), keeps the window off-screen and non-key.
    /// - Returns: Identifier of the newly opened window.
    @discardableResult
    func openWindow(
        app: AppState, initialQuery: String = "", initialMode: SearchMode = .names,
        inert: Bool = Presentation.inert
    ) -> UUID {
        let id = UUID()
        let model = app.makeSearchWindowModel()
        model.query = initialQuery
        model.mode = initialMode

        let window = Self.makeWindow(inert: inert)
        window.title = Self.windowTitle(for: initialQuery)

        let bridge = SearchWindowKeyBridge()
        window.keyBridge = bridge

        let rootView = SearchWindowView(
            model: model,
            savedStore: app.savedSearches,
            keyBridge: bridge,
            onNewWindow: { [weak self, weak app] in
                guard let self, let app else { return }
                _ = self.openWindow(app: app, inert: inert)
            },
            onTitleChange: { [weak window] query in
                window?.title = Self.windowTitle(for: query)
            }
        ).environmentObject(app)
        window.contentView = NSHostingView(rootView: rootView)

        position(window, inert: inert)

        windows[id] = window
        windowOrder.append(id)
        let closeToken = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.removeWindow(id: id, deferContentClear: true)
            }
        }
        let keyToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.markMostRecent(id: id)
            }
        }
        observers[id] = [closeToken, keyToken]

        if !inert { AppActivation.activate() }
        Presentation.present(window, inert: inert)
        return id
    }

    /// Brings the most recently used Search Window forward (and focuses its search field), or opens a new one if none exist.
    @discardableResult
    func activateOrOpen(app: AppState, inert: Bool = Presentation.inert) -> UUID {
        if let id = windowOrder.last, let win = windows[id] {
            if !inert {
                AppActivation.activate()
                win.deminiaturize(nil)
            }
            Presentation.present(win, inert: inert)
            let bridge = (win as? SearchBrowserWindow)?.keyBridge
            DispatchQueue.main.async { bridge?.focusSearch?() }
            return id
        }
        return openWindow(app: app, inert: inert)
    }

    /// Global-shortcut toggle when the user selects Search Window as their default UI:
    /// hides the app if a Search Window is already frontmost and no other FSearch windows (Settings/Debug/Onboarding)
    /// are visible, demotes the search window if other FSearch windows are open, or otherwise activates/opens a Search Window.
    func toggle(
        app: AppState, inert: Bool = Presentation.inert,
        appIsActive: Bool = NSApp.isActive, keyWindow: NSWindow? = NSApp.keyWindow,
        allWindows: [NSWindow] = NSApp.windows,
        hideApp: (() -> Void)? = nil
    ) {
        if appIsActive, let keyWindow, windows.values.contains(where: { $0 === keyWindow }) {
            if !inert {
                let searchSet = Set(windows.values.map(ObjectIdentifier.init))
                let hasOtherVisible = allWindows.contains { w in
                    !searchSet.contains(ObjectIdentifier(w)) && w.isVisible && !(w is NSPanel) && w.styleMask.contains(.titled)
                }
                if hasOtherVisible {
                    keyWindow.orderBack(nil)
                } else if let hideApp {
                    hideApp()
                } else {
                    NSApp.hide(nil)
                }
            }
            return
        }
        _ = activateOrOpen(app: app, inert: inert)
    }

    /// Centers the first search window and cascades subsequent ones so multiple windows stay visibly offset.
    func position(_ window: NSWindow, inert: Bool) {
        guard !inert else { return }
        if windows.isEmpty {
            window.center()
            cascadePoint = window.cascadeTopLeft(from: .zero)
        } else {
            cascadePoint = window.cascadeTopLeft(from: cascadePoint)
        }
    }

    /// Closes a single open search window by id.
    func closeWindow(id: UUID) {
        let win = windows[id]
        win?.close()
        removeWindow(id: id, deferContentClear: false)
        win?.contentView = nil
    }

    /// Closes all currently open search windows.
    func closeAll() {
        for id in Array(windows.keys) {
            closeWindow(id: id)
        }
    }

    private func markMostRecent(id: UUID) {
        guard windows[id] != nil else { return }
        windowOrder.removeAll { $0 == id }
        windowOrder.append(id)
    }

    private func removeWindow(id: UUID, deferContentClear: Bool) {
        let win = windows.removeValue(forKey: id)
        windowOrder.removeAll { $0 == id }
        if let tokens = observers.removeValue(forKey: id) {
            for token in tokens {
                NotificationCenter.default.removeObserver(token)
            }
        }
        if let win {
            if QuickLookSource.shared.isOwned(by: win) {
                QuickLookSource.shared.close()
            }
            if let browser = win as? SearchBrowserWindow {
                browser.keyBridge?.clear()
                browser.keyBridge = nil
            }
            // Release NSHostingView, SearchWindowView, SearchWindowModel, and its dedicated daemon sockets.
            // Defer when triggered by willCloseNotification so AppKit finishes NSWindow.close() first.
            if deferContentClear {
                DispatchQueue.main.async { win.contentView = nil }
            } else {
                win.contentView = nil
            }
        }
    }
}

/// Bridges AppKit window-level key equivalents (`⌥⌘P`, search-field focus, table first-responder tracking)
/// into the hosted `SearchWindowView`.
@MainActor
final class SearchWindowKeyBridge {
    var togglePreview: (() -> Void)?
    var focusSearch: (() -> Void)?
    var onTableFocusChanged: ((Bool) -> Void)?

    /// Breaks closure retain cycles when the hosting window closes or view disappears.
    func clear() {
        togglePreview = nil
        focusSearch = nil
        onTableFocusChanged = nil
    }
}

/// Search browser window that accepts `QLPreviewPanel` control (so ⌘Y Quick Look shows the file and toggles closed),
/// reports table first-responder changes for safe row-shortcut gating, and handles `⌥⌘P` preview toggling reliably.
class SearchBrowserWindow: NSWindow {
    var keyBridge: SearchWindowKeyBridge?

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let ok = super.makeFirstResponder(responder)
        if ok {
            keyBridge?.onTableFocusChanged?(SearchWindowView.firstResponderAllowsRowShortcuts(firstResponder))
        }
        return ok
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { QuickLookSource.shared.attach(panel, owner: self) }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated { QuickLookSource.shared.detach(panel, owner: self) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if !event.isARepeat,
            Self.isTogglePreviewEvent(
                characters: event.charactersIgnoringModifiers ?? "",
                modifiers: event.modifierFlags, keyCode: event.keyCode),
            let toggle = keyBridge?.togglePreview
        {
            toggle()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// True for `⌥⌘P` (exact Option+Command modifiers). Checks ASCII Latin characters first so Dvorak `⌥⌘L`
    /// (key code 35) never misfires, falling back to physical key code 35 for non-Latin layouts or Option-dead keys (`π`).
    nonisolated static func isTogglePreviewEvent(
        characters: String, modifiers: NSEvent.ModifierFlags, keyCode: UInt16
    ) -> Bool {
        let mods = modifiers.intersection([.command, .option, .control, .shift])
        guard mods == [.command, .option] else { return false }
        let lower = characters.lowercased()
        if lower.count == 1, let scalar = lower.unicodeScalars.first, scalar >= "a" && scalar <= "z" {
            return lower == "p"
        }
        return keyCode == 35
    }
}

/// Non-activating window used under `Presentation.inert` so unit tests never take keyboard focus.
private final class InertSearchWindow: SearchBrowserWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
