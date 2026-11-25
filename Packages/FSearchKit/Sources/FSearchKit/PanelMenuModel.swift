import Foundation

/// What a row of the panel's FSearch menu (⌘/) does; the app carries it out.
public enum PanelMenuAction: CaseIterable, Hashable, Sendable {
    /// The rows, in menu order.
    case sendFeedback, manual, keyboardShortcuts, changelog, about, settings, github, discussions, quit
}

/// One row of the FSearch menu.
public struct PanelMenuItem: Equatable, Identifiable, Sendable {
    public let action: PanelMenuAction
    /// The row title.
    public let title: String
    /// The SF Symbol name for the row icon.
    public let symbol: String
    /// Secondary text on the right, only where it adds information.
    public let detail: String?
    /// The shortcut as keycaps, one symbol per key (["⌘", ","]); empty for none.
    public let shortcut: [String]
    /// More words the filter matches besides the title.
    public let keywords: [String]

    /// Stable English identifier used for accessibility ids (`appMenu-Settings`), independent of localization.
    public var id: String {
        switch action {
        case .sendFeedback: "Send Feedback"
        case .manual: "Manual"
        case .keyboardShortcuts: "Keyboard Shortcuts"
        case .changelog: "Changelog"
        case .about: "About FSearch"
        case .settings: "Settings"
        case .github: "GitHub"
        case .discussions: "Discussions"
        case .quit: "Quit FSearch"
        }
    }

    /// Whether the filter text `q` (already trimmed and lowercased) matches the title or a keyword.
    func matches(_ q: String) -> Bool {
        q.isEmpty || title.lowercased().contains(q) || keywords.contains { $0.contains(q) }
    }
}

/// A group of rows, with an optional small header above it.
public struct PanelMenuSection: Equatable, Sendable {
    /// The header ("Community"), or nil for none.
    public let title: String?
    public let items: [PanelMenuItem]
}

/// What the app must do after the menu handles a key or a click.
public enum PanelMenuOutcome: Equatable, Sendable {
    /// Nothing beyond the state change.
    case none
    /// The menu closed.
    case close
    /// The menu closed; run this row's action.
    case run(PanelMenuAction)
}

/// The panel's FSearch menu (⌘/ or the footer's gear): rows, filter, selection and whether it is open.
///
/// No UI involved, so every binding is testable. The selection indexes ``visibleItems``.
public struct PanelMenuModel: Equatable, Sendable {
    /// Every row, grouped as the menu draws them.
    public static let sections: [PanelMenuSection] = [
        PanelMenuSection(
            title: nil,
            items: [
                item(
                    .sendFeedback, String(localized: "Send Feedback", bundle: .module), "bubble.left",
                    keywords: ["bug", "issue", "feedback", "problem"]),
                item(
                    .manual, String(localized: "Manual", bundle: .module), "questionmark.circle",
                    keywords: ["help", "docs", "documentation", "guide"]),
                item(
                    .keyboardShortcuts, String(localized: "Keyboard Shortcuts", bundle: .module), "keyboard",
                    keywords: ["keys", "hotkeys"]),
                item(
                    .changelog, String(localized: "Changelog", bundle: .module), "doc.text",
                    keywords: ["release notes", "what's new", "version"]),
                item(
                    .about, String(localized: "About FSearch", bundle: .module), "info.circle",
                    keywords: ["version", "info"]),
                item(
                    .settings, String(localized: "Settings…", bundle: .module), "gearshape", shortcut: ["⌘", ","],
                    keywords: ["preferences", "prefs"]),
            ]),
        PanelMenuSection(
            title: String(localized: "Community", bundle: .module),
            items: [
                item(
                    .github, "GitHub", "chevron.left.forwardslash.chevron.right", detail: "domfahey/fsearch-app",
                    keywords: ["repository", "source", "code"]),
                item(
                    .discussions, String(localized: "Discussions", bundle: .module), "bubble.left.and.bubble.right",
                    keywords: ["community", "forum", "questions"]),
            ]),
        PanelMenuSection(
            title: nil,
            items: [item(.quit, String(localized: "Quit FSearch", bundle: .module), "power", shortcut: ["⌘", "Q"], keywords: ["exit"])]),
    ]

    private static func item(
        _ action: PanelMenuAction, _ title: String, _ symbol: String, detail: String? = nil, shortcut: [String] = [],
        keywords: [String]
    ) -> PanelMenuItem {
        PanelMenuItem(action: action, title: title, symbol: symbol, detail: detail, shortcut: shortcut, keywords: keywords)
    }

    /// The header text: "FSearch v0.1.0 (42)", or without the build when there is none.
    public static func header(version: String, build: String) -> String {
        build.isEmpty ? "FSearch v\(version)" : "FSearch v\(version) (\(build))"
    }

    /// The header as VoiceOver reads it: "FSearch version 0.1.0 (42)".
    public static func headerLabel(version: String, build: String) -> String {
        build.isEmpty
            ? String(localized: "FSearch version \(version)", bundle: .module)
            : String(localized: "FSearch version \(version) (\(build))", bundle: .module)
    }

    /// Whether the menu is showing.
    public private(set) var isOpen = false
    /// The text in "Search for actions…"; changing it selects the first match.
    public var filter = "" {
        didSet { if filter != oldValue { selection = 0 } }
    }
    /// The selected row among ``visibleItems``; read through ``selected``, which clamps it.
    public var selection = 0

    public init() {}

    /// The sections with a row matching the filter, holding only those rows.
    public var visibleSections: [PanelMenuSection] {
        let q = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Self.sections.compactMap { s in
            let items = s.items.filter { $0.matches(q) }
            return items.isEmpty ? nil : PanelMenuSection(title: s.title, items: items)
        }
    }

    /// The selectable rows showing, in order (headers and dividers aren't rows).
    public var visibleItems: [PanelMenuItem] { visibleSections.flatMap(\.items) }

    /// Nothing matches the filter ("No matching actions").
    public var isEmpty: Bool { visibleItems.isEmpty }

    /// The row ↵ would run, if any.
    public var selected: PanelMenuItem? {
        let items = visibleItems
        guard !items.isEmpty else { return nil }
        return items[min(max(0, selection), items.count - 1)]
    }

    /// Opens the menu with an empty filter and the first row selected.
    public mutating func open() {
        filter = ""
        selection = 0
        isOpen = true
    }

    /// Closes the menu.
    public mutating func close() { isOpen = false }

    /// ⌘/ or the gear: opens a closed menu, closes an open one.
    public mutating func toggle() { isOpen ? close() : open() }

    /// Selects a showing row (mouse hover); a hidden one changes nothing.
    public mutating func select(_ action: PanelMenuAction) {
        if let i = visibleItems.firstIndex(where: { $0.action == action }) { selection = i }
    }

    /// A click on a showing row: close and run it.
    public mutating func choose(_ action: PanelMenuAction) -> PanelMenuOutcome {
        guard visibleItems.contains(where: { $0.action == action }) else { return .none }
        close()
        return .run(action)
    }

    /// What a panel key does while the menu is open.
    ///
    /// ↑/↓ (and ⌃P/⌃N, which arrive as them) move and wrap; ↵ runs the selected row;
    /// Esc clears the filter, then closes; ⌘/ closes. Other keys do nothing.
    public mutating func handle(_ key: PanelKey) -> PanelMenuOutcome {
        let count = visibleItems.count
        switch key {
        case .up, .down:
            guard count > 0 else { selection = 0; return .none }
            let current = min(max(0, selection), count - 1)
            selection = (current + (key == .down ? 1 : -1) + count) % count
            return .none
        case .enter:
            guard let item = selected else { return .none }
            close()
            return .run(item.action)
        case .escape:
            if !filter.isEmpty { filter = ""; return .none }
            close()
            return .close
        case .appMenu:
            close()
            return .close
        case .cmdEnter, .cmdY, .cmdShiftC, .cmdDigit, .cmdK, .backspaceOnEmpty:
            return .none
        }
    }
}
