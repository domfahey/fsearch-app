import AppKit
import FSearchKit
import SwiftUI

/// The panel's keyboard and effect routing, apart from SwiftUI so each binding is testable.
enum PanelInput {
    /// The parts of a key press the panel looks at.
    struct Press: Equatable {
        var key: KeyEquivalent
        var characters: String
        var command = false, shift = false, control = false
        /// The physical key (an ANSI kVK_ code), for ⌘ letters on a non-Latin layout.
        var keyCode: UInt16?
        /// The key is being held down (KeyPress.Phases.repeat).
        var isRepeat = false

        init(
            key: KeyEquivalent, characters: String = "", command: Bool = false, shift: Bool = false, control: Bool = false,
            keyCode: UInt16? = nil, isRepeat: Bool = false
        ) {
            (self.key, self.characters, self.command, self.shift, self.control) = (key, characters, command, shift, control)
            (self.keyCode, self.isRepeat) = (keyCode, isRepeat)
        }

        /// SwiftUI's KeyPress has no key code; the key-down AppKit is
        /// dispatching right now does.
        init(_ p: KeyPress, event: NSEvent?) {
            let code = event.flatMap { $0.type == .keyDown ? $0.keyCode : nil }
            self.init(
                key: p.key, characters: p.characters, command: p.modifiers.contains(.command),
                shift: p.modifiers.contains(.shift), control: p.modifiers.contains(.control),
                keyCode: code, isRepeat: p.phase == .repeat)
        }
    }

    /// Which panel key a press is, if any. Delete is a key only on an empty
    /// query. Held down, only the moving keys (↑ ↓ ⌃P ⌃N) repeat.
    static func key(for p: Press, queryIsEmpty: Bool) -> PanelKey? {
        guard let k = firstKey(for: p, queryIsEmpty: queryIsEmpty) else { return nil }
        return !p.isRepeat || k == .up || k == .down ? k : nil
    }

    private static func firstKey(for p: Press, queryIsEmpty: Bool) -> PanelKey? {
        // ⌃ letters can arrive as control characters (⌃N is U+000E).
        let ctrlLetter = p.control && !p.command && !p.shift ? letter(p.key.character) : nil
        if ctrlLetter == "p" { return .up }
        if ctrlLetter == "n" { return .down }
        switch (p.key, p.command, p.shift, p.control) {
        case (.upArrow, _, _, _): return .up
        case (.downArrow, _, _, _): return .down
        case (.return, true, _, _): return .cmdEnter
        case (.return, false, _, _): return .enter
        case (.escape, _, _, _): return .escape
        // ⌘Y, ⌘K, ⌘⇧C ignoring case (Shift or Caps Lock change the character),
        // or by key code on a non-Latin layout.
        case (_, true, _, _) where commandLetter(p) != nil: return commandLetter(p)
        case (.delete, false, _, _) where queryIsEmpty: return .backspaceOnEmpty
        default:
            // ⌘1–9 only; a plain digit is typed into the field.
            guard p.command, let n = p.characters.first?.wholeNumberValue else { return nil }
            return .cmdDigit(n)
        }
    }

    private static func commandLetter(_ p: Press) -> PanelKey? {
        PanelKey.commandLetter(String(p.key.character), shift: p.shift, keyCode: p.keyCode)
    }

    /// The letter a key is, lowercased, turning a control character back into its letter.
    static func letter(_ c: Character) -> Character? {
        guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return nil }
        if (1...26).contains(v) { return Character(UnicodeScalar(v + 0x60)!) }
        return Character(String(c).lowercased())
    }

    enum Route: Equatable {
        /// Pass the effect to the controller; its indexes are file indexes.
        case perform(PanelEffect)
        /// Return on a "use with..." row: search again in that mode.
        case switchMode(SearchMode)
        /// Return on an app-command row.
        case runCommand(AppCommand)
        case ignore
    }

    /// Effects arrive with row indexes. Command rows run on Return and take no
    /// file action; "use with..." rows switch mode on Return and take none either;
    /// file rows pass through with their file index.
    static func route(_ effect: PanelEffect, rows: PanelRows) -> Route {
        switch effect {
        case let .open(i):
            switch rows.row(at: i) {
            case let .result(f): return .perform(.open(f))
            case let .command(c): return .runCommand(c)
            case let .some(r): return r.mode.map(Route.switchMode) ?? .ignore
            case nil: return .ignore
            }
        case let .reveal(i): return fileEffect(rows, i) { .reveal($0) }
        case let .quickLook(i): return fileEffect(rows, i) { .quickLook($0) }
        case let .copyPath(i): return fileEffect(rows, i) { .copyPath($0) }
        case let .showActions(i): return fileEffect(rows, i) { .showActions($0) }
        case .none, .hide: return .perform(effect)
        }
    }

    private static func fileEffect(_ rows: PanelRows, _ i: Int, _ make: (Int) -> PanelEffect) -> Route {
        if case let .result(f)? = rows.row(at: i) { return .perform(make(f)) }
        return .ignore
    }

    static func route(_ effect: PanelEffect, files: Int, query: String, mode: SearchMode) -> Route {
        route(effect, rows: PanelRows(files: files, query: query, mode: mode))
    }

    /// The id of the view for row `i`, which the list scrolls to when the
    /// keyboard selects it. File rows use their result's id, as the list does.
    static func rowID(at i: Int, shown: [ResultItem], rows: PanelRows) -> String? {
        switch rows.row(at: i) {
        case let .result(f): shown.indices.contains(f) ? shown[f].id : nil
        case let .command(c): "command-\(c.title)"
        case .searchInside: "fallback-content"
        case .findDefinitions: "fallback-symbols"
        case nil: nil
        }
    }

    /// Whether the rows answer what is in the box. Recents (an empty names
    /// query) wait on no search.
    @MainActor
    static func rowsAreCurrent(_ model: SearchModel) -> Bool {
        model.resultsAreCurrent || (model.query.isEmpty && model.mode == .names)
    }

    /// The key to act on now, or nil while a result key waits for the results
    /// of the query in the box (paste + ↵, ↵ during a slow grep).
    @MainActor
    static func gate(_ key: PanelKey, held: inout HeldKey, model: SearchModel) -> PanelKey? {
        held.press(key, current: rowsAreCurrent(model), query: model.query, mode: model.mode)
    }

    /// A held key to run now that the results answer its query, if they do.
    @MainActor
    static func replay(held: inout HeldKey, model: SearchModel) -> PanelKey? {
        guard held.held != nil, rowsAreCurrent(model) else { return nil }
        return held.resultsArrived(query: model.query, mode: model.mode)
    }

    /// The ⌘K menu action an effect is, so a key and its menu item agree on hiding the panel.
    static func menuAction(for effect: PanelEffect) -> MenuAction? {
        switch effect {
        case .open: .open
        case .reveal: .reveal
        case .quickLook: .quickLook
        case .copyPath: .copyPath
        case .showActions, .none, .hide: nil
        }
    }
}
