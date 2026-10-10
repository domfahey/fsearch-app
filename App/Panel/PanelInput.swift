import FSearchKit
import SwiftUI

/// The panel's keyboard and effect routing, apart from SwiftUI so each binding is testable.
enum PanelInput {
    /// The parts of a key press the panel looks at.
    struct Press: Equatable {
        var key: KeyEquivalent
        var characters: String
        var command = false, shift = false, control = false

        init(key: KeyEquivalent, characters: String = "", command: Bool = false, shift: Bool = false, control: Bool = false) {
            (self.key, self.characters, self.command, self.shift, self.control) = (key, characters, command, shift, control)
        }

        init(_ p: KeyPress) {
            self.init(key: p.key, characters: p.characters, command: p.modifiers.contains(.command),
                      shift: p.modifiers.contains(.shift), control: p.modifiers.contains(.control))
        }
    }

    /// Which panel key a press is, if any. Delete is a key only on an empty query.
    static func key(for p: Press, queryIsEmpty: Bool) -> PanelKey? {
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
        // ⌘Y, ⌘K, ⌘⇧C ignoring case: Shift or Caps Lock change the character.
        case (_, true, _, _) where PanelKey.commandLetter(String(p.key.character), shift: p.shift) != nil:
            return PanelKey.commandLetter(String(p.key.character), shift: p.shift)
        case (.delete, false, _, _) where queryIsEmpty: return .backspaceOnEmpty
        default:
            // ⌘1–9 only; a plain digit is typed into the field.
            guard p.command, let n = p.characters.first?.wholeNumberValue else { return nil }
            return .cmdDigit(n)
        }
    }

    /// The letter a key is, lowercased, turning a control character back into its letter.
    static func letter(_ c: Character) -> Character? {
        guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return nil }
        if (1...26).contains(v) { return Character(UnicodeScalar(v + 0x60)!) }
        return Character(String(c).lowercased())
    }

    enum Route: Equatable {
        /// Pass the effect to the controller.
        case perform(PanelEffect)
        /// Return on a "use with..." row: search again in that mode.
        case switchMode(SearchMode)
        case ignore
    }

    /// Rows past the files are the "use with..." rows: Return switches mode,
    /// file actions don't apply to them.
    static func route(_ effect: PanelEffect, files: Int, query: String, mode: SearchMode) -> Route {
        switch effect {
        case let .open(i) where i >= files:
            if let m = PanelRows.row(at: i, files: files, query: query, mode: mode)?.mode { return .switchMode(m) }
            return .ignore
        case let .reveal(i), let .quickLook(i), let .copyPath(i), let .showActions(i):
            return i < files ? .perform(effect) : .ignore
        default:
            return .perform(effect)
        }
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
