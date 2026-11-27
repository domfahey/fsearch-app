import AppKit
import FSearchKit
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

    /// Open windows keyed by identifier; cleaned up automatically on close.
    private(set) var windows: [UUID: NSWindow] = [:]
    private var observers: [UUID: NSObjectProtocol] = [:]
    private var cascadePoint = NSPoint.zero

    /// Number of currently open search windows.
    var openCount: Int { windows.count }

    /// Computes the window title from the current search query.
    static func windowTitle(for query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "FSearch") : "FSearch — \(DisplaySafe.name(trimmed))"
    }

    /// Creates an `NSWindow` configured for a search browser (inert non-key window in unit tests).
    static func makeWindow(size: NSSize = NSSize(width: 1080, height: 680), inert: Bool = Presentation.inert) -> NSWindow {
        let style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        let origin = inert ? NSPoint(x: -20_000, y: -20_000) : .zero
        let window: NSWindow =
            inert
            ? InertSearchWindow(contentRect: NSRect(origin: origin, size: size), styleMask: style, backing: .buffered, defer: false)
            : NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: style, backing: .buffered, defer: false)
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

        let rootView = SearchWindowView(
            model: model,
            savedStore: app.savedSearches,
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
        observers[id] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.removeWindow(id: id)
            }
        }

        Presentation.present(window, inert: inert)
        return id
    }

    /// Centers the first search window and cascades subsequent ones so multiple windows stay visible.
    func position(_ window: NSWindow, inert: Bool) {
        guard !inert else { return }
        if windows.isEmpty {
            window.center()
            cascadePoint = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        } else {
            cascadePoint = window.cascadeTopLeft(from: cascadePoint)
        }
    }

    /// Closes a single open search window by id.
    func closeWindow(id: UUID) {
        windows[id]?.close()
        removeWindow(id: id)
    }

    /// Closes all currently open search windows.
    func closeAll() {
        for id in Array(windows.keys) {
            closeWindow(id: id)
        }
    }

    private func removeWindow(id: UUID) {
        windows.removeValue(forKey: id)
        if let token = observers.removeValue(forKey: id) {
            NotificationCenter.default.removeObserver(token)
        }
    }
}

/// Non-activating window used under `Presentation.inert` so unit tests never take keyboard focus.
private final class InertSearchWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
