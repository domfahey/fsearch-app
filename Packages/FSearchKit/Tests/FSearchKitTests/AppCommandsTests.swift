import Testing

@testable import FSearchKit

@Suite struct AppCommandsTests {
    @Test(arguments: ["se", "set", "settings", "Settings", "SETT", "pref", "prefs", "preferences", "pr", "  set  "])
    func matchesSettings(_ q: String) {
        #expect(AppCommand.matches(q) == [.settings])
    }

    @Test(arguments: ["", " ", "s", "p", "x", "sets", "settingsx", "prefsx", "set up", "grep:set", "fi", "se tt"])
    func doesNotMatch(_ q: String) {
        #expect(AppCommand.matches(q).isEmpty)
    }

    @Test func titleAndSymbol() {
        #expect(AppCommand.settings.title == "FSearch Settings")
        #expect(!AppCommand.settings.symbol.isEmpty)
    }
}

@Suite struct PanelRowsCommandTests {
    @Test func commandRowsComeFirstThenFilesThenFallbacks() {
        let rows = PanelRows(files: 2, query: "set", mode: .names)
        #expect(rows.commands == [.settings])
        #expect(rows.count == 5)
        #expect(rows.row(at: 0) == .command(.settings))
        #expect(rows.row(at: 1) == .result(0))
        #expect(rows.row(at: 2) == .result(1))
        #expect(rows.row(at: 3) == .searchInside)
        #expect(rows.row(at: 4) == .findDefinitions)
        #expect(rows.row(at: 5) == nil)
        #expect(rows.row(at: -1) == nil)
    }

    @Test func noCommandKeepsFileIndexing() {
        let rows = PanelRows(files: 2, query: "heron", mode: .names)
        #expect(rows.commands.isEmpty)
        #expect(rows.row(at: 0) == .result(0))
    }

    @Test(arguments: [SearchMode.content, .symbols])
    func neverInContentOrSymbolMode(_ mode: SearchMode) {
        let rows = PanelRows(files: 2, query: "settings", mode: mode)
        #expect(rows.commands.isEmpty)
        #expect(rows.count == 2)
        #expect(rows.row(at: 0) == .result(0))
    }

    @Test func commandWithNoFiles() {
        let rows = PanelRows(files: 0, query: "prefs", mode: .names)
        #expect(rows.row(at: 0) == .command(.settings))
        #expect(rows.row(at: 1) == .searchInside)
    }

    @Test func commandNeverAnswersAFileAction() {
        var s = PanelState(query: "set", selection: 0, count: 5, files: 2, commands: 1)
        #expect(reduce(&s, .cmdDigit(1)) == .open(1))
        #expect(reduce(&s, .cmdDigit(2)) == .open(2))
        #expect(reduce(&s, .cmdDigit(3)) == .none)
        #expect(reduce(&s, .enter) == .open(0))
    }
}
