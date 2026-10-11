import AppKit
import FSearchKit
import SwiftUI

/// The panel's keyboard and effect routing, apart from SwiftUI so each binding is testable.
enum PanelInput {
    /// The parts of a key press the panel looks at.
    struct Press: Equatable {
        var key: KeyEquivalent
        var characters: String
        var command = false, shift = false, control = false, option = false
        /// The physical key (an ANSI kVK_ code), for ⌘ letters on a non-Latin layout.
        var keyCode: UInt16?
        /// The key is being held down (KeyPress.Phases.repeat).
        var isRepeat = false

        init(
            key: KeyEquivalent, characters: String = "", command: Bool = false, shift: Bool = false, control: Bool = false,
            option: Bool = false, keyCode: UInt16? = nil, isRepeat: Bool = false
        ) {
            (self.key, self.characters, self.command, self.shift, self.control) = (key, characters, command, shift, control)
            self.option = option
            (self.keyCode, self.isRepeat) = (keyCode, isRepeat)
        }

        /// SwiftUI's KeyPress has no key code; the key-down AppKit is
        /// dispatching right now does.
        init(_ p: KeyPress, event: NSEvent?) {
            let code = event.flatMap { $0.type == .keyDown ? $0.keyCode : nil }
            self.init(
                key: p.key, characters: p.characters, command: p.modifiers.contains(.command),
                shift: p.modifiers.contains(.shift), control: p.modifiers.contains(.control),
                option: p.modifiers.contains(.option), keyCode: code, isRepeat: p.phase == .repeat)
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
        let ctrlLetter = p.control && !p.command && !p.shift && !p.option ? letter(p.key.character) : nil
        if ctrlLetter == "p" { return .up }
        if ctrlLetter == "n" { return .down }
        // Moving and Escape take any modifiers.
        switch p.key {
        case .upArrow: return .up
        case .downArrow: return .down
        case .escape: return .escape
        default: break
        }
        // ↵ and the ⌘ shortcuts take no ⌃ or ⌥: ⌘⌃Y is not ⌘Y.
        if p.control || p.option, p.key == .return || p.command { return nil }
        switch (p.key, p.command, p.shift, p.control) {
        case (.return, true, _, _): return .cmdEnter
        case (.return, false, _, _): return .enter
        // ⌘Y, ⌘K, ⌘⇧C ignoring case (Shift or Caps Lock change the character),
        // or by key code on a non-Latin layout.
        case (_, true, _, _) where commandLetter(p) != nil: return commandLetter(p)
        // ⌘/ opens the FSearch menu: by character, or by key code (kVK_ANSI_Slash) on other layouts.
        case (_, true, false, _) where p.characters == "/" || p.keyCode == 0x2C: return .appMenu
        // Backspace: SwiftUI's .delete is BS, a keyboard sends DEL; key code 51 either way.
        case (_, false, _, _) where queryIsEmpty && isBackspace(p): return .backspaceOnEmpty
        default:
            // ⌘1–9 only; a plain digit is typed into the field.
            guard p.command, let n = p.characters.first?.wholeNumberValue else { return nil }
            return .cmdDigit(n)
        }
    }

    private static func isBackspace(_ p: Press) -> Bool {
        p.key == .delete || p.key.character == "\u{7F}" || p.keyCode == 51
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

    /// A press that is no panel key but must not reach the field either: ⌃↵
    /// and ⌥↵ would type a line break into the query, and a ⌘ shortcut with
    /// ⌃ or ⌥ added should do nothing. The view takes these and does nothing.
    static func swallows(_ p: Press) -> Bool {
        guard p.control || p.option else { return false }
        if p.key == .return { return true }
        var bare = p
        (bare.control, bare.option) = (false, false)
        return p.command && firstKey(for: bare, queryIsEmpty: false) != nil
    }

    /// A held ⌘K replays a main-actor turn later, so its menu opens where the
    /// new rows have been laid out, not where the old ones were.
    static func replaysAfterLayout(_ k: PanelKey) -> Bool { k == .cmdK }

    /// The file Quick Look follows to when row `i` is selected; nil on a command or fallback row.
    static func previewPath(at i: Int, shown: [ResultItem], rows: PanelRows) -> String? {
        guard case let .result(f)? = rows.row(at: i), shown.indices.contains(f) else { return nil }
        return shown[f].path
    }

    /// What the view does with an effect once row indices are resolved.
    enum Route: Equatable {
        /// Pass the effect to the controller; its indexes are file indexes.
        case perform(PanelEffect)
        /// Return on a "use with..." row: search again in that mode.
        case switchMode(SearchMode)
        /// Return on an app-command row.
        case runCommand(AppCommand)
        /// Nothing: the row takes no such action.
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

    /// Re-targets a file-only effect to its file index, or ignores it on a command or fallback row.
    private static func fileEffect(_ rows: PanelRows, _ i: Int, _ make: (Int) -> PanelEffect) -> Route {
        if case let .result(f)? = rows.row(at: i) { return .perform(make(f)) }
        return .ignore
    }

    #if DEBUG
        /// Convenience for tests: builds the rows from their inputs.
        static func route(_ effect: PanelEffect, files: Int, query: String, mode: SearchMode) -> Route {
            route(effect, rows: PanelRows(files: files, query: query, mode: mode))
        }
    #endif

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
    /// query) wait on no search. A filter still being typed (`foo ext:`) keeps
    /// the results of the query it extends in the same mode, and no search runs
    /// until it is finished, so those rows count too. A pasted tail that only
    /// starts with the answered query (`food ext:` over `foo`) doesn't.
    @MainActor
    static func rowsAreCurrent(_ model: SearchModel) -> Bool {
        if model.resultsAreCurrent || (model.query.isEmpty && model.mode == .names) { return true }
        return model.phase == .results && model.mode == model.answered.mode
            && QuerySplit.halfTypedExtends(model.query, answered: model.answered.query, mode: model.mode)
    }

    /// The key to act on now, or nil while a result key waits for the results
    /// of the query in the box (paste + ↵, ↵ during a slow grep).
    @MainActor
    static func gate(_ key: PanelKey, held: inout HeldKey, model: SearchModel) -> PanelKey? {
        held.press(key, current: rowsAreCurrent(model), query: model.query, mode: model.mode)
    }

    /// A held key to run now that the results answer its query, if they do.
    ///
    /// Only results the user can see replay it: a hidden panel, or a failed or indexing settle (a ↵ on zero files
    /// would land on a fallback row and switch mode), drops it instead.
    @MainActor
    static func replay(held: inout HeldKey, model: SearchModel, visible: Bool) -> PanelKey? {
        guard held.held != nil, rowsAreCurrent(model) else { return nil }
        guard visible, model.phase == .results else {
            held.cancel()
            return nil
        }
        return held.resultsArrived(query: model.query, mode: model.mode)
    }

    /// What the rows answer, as the view watches it.
    struct Answer: Equatable {
        var query: String
        var mode: SearchMode
        var current: Bool
    }

    /// The model's ``Answer`` now.
    @MainActor
    static func answer(_ model: SearchModel) -> Answer {
        Answer(query: model.answered.query, mode: model.answered.mode, current: rowsAreCurrent(model))
    }

    /// The rows changed. Rows for another query make a selection made on the
    /// old ones meaningless, so it goes back to the top, and only then does a
    /// held key replay (one handler, so the order is fixed).
    ///
    /// - Returns: The held key to run, if any.
    @MainActor
    static func rowsChanged(
        from old: Answer, to new: Answer, selection: inout Int, held: inout HeldKey, model: SearchModel, visible: Bool
    ) -> PanelKey? {
        if old.query != new.query || old.mode != new.mode { selection = 0 }
        return new.current ? replay(held: &held, model: model, visible: visible) : nil
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

/// The panel's held key (see ``HeldKey``), owned by ``PanelController`` so
/// hiding the panel drops it; the view reads and writes it.
@MainActor
final class HeldKeyBox {
    var key = HeldKey()
}

/// Keys for the panel from outside its own key handling: ↑/↓ pressed in
/// Quick Look, which holds the keyboard while it is up.
@MainActor @Observable
final class PanelKeyFeed {
    /// A key sent, numbered so the same key twice is still a change.
    struct Sent: Equatable {
        let key: PanelKey
        let n: Int
    }

    /// The last key sent; the view acts on each new one.
    private(set) var last: Sent?

    /// Sends a key to the panel.
    func send(_ k: PanelKey) { last = Sent(key: k, n: (last?.n ?? 0) + 1) }
}
