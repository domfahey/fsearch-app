import AppKit
import FSearchKit
import Observation
import SwiftUI

/// The panel's FSearch menu as the view and ``PanelController`` share it.
///
/// Owned by the controller, so hiding the panel closes the menu.
@MainActor @Observable
final class AppMenuState {
    /// Rows, filter, selection and whether the menu is open.
    var model = PanelMenuModel() {
        didSet { syncOpen() }
    }

    /// Open or closed, kept apart from ``model`` so the panel redraws only when this changes, not on every keystroke in
    /// the filter.
    private(set) var isOpen = false

    /// The panel's held result key, dropped when the menu opens so it never runs behind the menu.
    @ObservationIgnored private let held: HeldKeyBox?

    init(held: HeldKeyBox? = nil) { self.held = held }

    private func syncOpen() {
        guard model.isOpen != isOpen else { return }
        isOpen = model.isOpen
        if isOpen { held?.key.cancel() }
    }

    /// ⌘/ or the gear: opens a closed menu, closes an open one.
    func toggle() { model.toggle() }

    func close() { model.close() }

    /// A key press, while the menu is open or for ⌘/.
    ///
    /// - Returns: nil when the panel should handle the key itself (the menu is closed and it isn't ⌘/);
    ///   `.ignored` for typing, so the filter field gets it; `.handled` otherwise.
    func handle(_ p: PanelInput.Press, run: (PanelMenuAction) -> Void) -> KeyPress.Result? {
        // The filter field's own Backspace is never the panel's "drop the chip".
        let key = PanelInput.key(for: p, queryIsEmpty: false)
        guard model.isOpen else {
            guard key == .appMenu else { return nil }
            model.open()
            return .handled
        }
        // Tab would move the keyboard to the search field behind the menu.
        if p.key == .tab || p.key.character == "\u{19}" { return .handled }
        guard let key else { return .ignored }
        perform(model.handle(key), run)
        return .handled
    }

    /// A click on a row.
    func choose(_ action: PanelMenuAction, run: (PanelMenuAction) -> Void) {
        perform(model.choose(action), run)
    }

    private func perform(_ outcome: PanelMenuOutcome, _ run: (PanelMenuAction) -> Void) {
        if case let .run(action) = outcome { run(action) }
    }
}

/// What the FSearch menu's rows do. Links open through ``FileActions/workspace``;
/// About and Quit go through seams, so tests never show a window or quit the host.
@MainActor
enum AppMenuActions {
    /// Shows the standard About panel, as the menu bar's About FSearch does. Never in the unit-test host.
    static var showAbout: @MainActor () -> Void = live {
        AppActivation.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    /// Quits the app. Never in the unit-test host; tests replace it.
    static var quit: @MainActor () -> Void = live { NSApp.terminate(nil) }

    /// Wraps `perform` so it does nothing while `inert` (read on every call) is true.
    static func live(
        inert: @escaping @MainActor () -> Bool = { Presentation.inert }, _ perform: @escaping @MainActor () -> Void
    ) -> @MainActor () -> Void {
        { if !inert() { perform() } }
    }

    /// The Help page a row opens, looked up by its title in ``HelpLinks``; nil for rows that aren't links.
    static func url(for action: PanelMenuAction) -> URL? {
        let title: String? =
            switch action {
            case .manual: "FSearch Help"
            case .keyboardShortcuts: "Keyboard Shortcuts"
            case .changelog: "Changelog"
            case .github: "GitHub"
            case .discussions: "Discussions"
            case .sendFeedback, .about, .settings, .quit: nil
            }
        return title.flatMap(HelpLinks.item)?.url
    }

    /// Runs a row. Every row but Quit puts the launcher away, since each goes to another window or app.
    static func run(_ action: PanelMenuAction, app: AppState) {
        switch action {
        case .sendFeedback:
            app.panel.hide(returnFocus: false)
            HelpLinks.reportIssue(daemon: app.daemon, workspace: FileActions.workspace)
        case .manual, .keyboardShortcuts, .changelog, .github, .discussions:
            app.panel.hide(returnFocus: false)
            if let url = url(for: action) { FileActions.workspace.open(url) }
        case .about:
            app.panel.hide(returnFocus: false)
            showAbout()
        case .settings:
            // The same steps as the panel's FSearch Settings row (PanelController.run).
            PanelController.openSettings()
            app.panel.hide(returnFocus: false)
        case .quit:
            quit()
        }
    }

    /// The app's short version and build, the strings the bug report sends.
    static func version(_ bundle: Bundle = .main) -> (version: String, build: String) {
        let info = bundle.infoDictionary
        return (info?["CFBundleShortVersionString"] as? String ?? "unknown", info?["CFBundleVersion"] as? String ?? "")
    }

    /// The menu's header: "FSearch v0.1.0 (42)".
    static func header() -> String {
        let v = version()
        return PanelMenuModel.header(version: v.version, build: v.build)
    }
}
