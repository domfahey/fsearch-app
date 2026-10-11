import Testing

@testable import FSearchKit

@Suite struct PanelMenuModelTests {
    private func titles(_ m: PanelMenuModel) -> [String] { m.visibleItems.map(\.title) }

    @Test func rowsAndSectionsInOrder() {
        let m = PanelMenuModel()
        #expect(
            titles(m) == [
                "Send Feedback", "Manual", "Keyboard Shortcuts", "Changelog", "About FSearch", "Settings…",
                "GitHub", "Discussions", "Quit FSearch",
            ])
        #expect(m.visibleSections.map(\.title) == [nil, "Community", nil])
        #expect(PanelMenuModel.sections.flatMap(\.items).map(\.action) == PanelMenuAction.allCases)
    }

    @Test func badgesAndDetails() {
        let all = PanelMenuModel.sections.flatMap(\.items)
        let badges = Dictionary(uniqueKeysWithValues: all.map { ($0.title, $0.shortcut) })
        #expect(badges["Settings…"] == ["⌘", ","])
        #expect(badges["Quit FSearch"] == ["⌘", "Q"])
        // ⌘/ opens this menu, so its own row shows no badge.
        #expect(badges["Keyboard Shortcuts"] == [])
        #expect(all.filter { !$0.shortcut.isEmpty }.map(\.title) == ["Settings…", "Quit FSearch"])
        #expect(all.compactMap(\.detail) == ["domfahey/fsearch-app"])
        #expect(all.allSatisfy { !$0.symbol.isEmpty })
        // Identifiers drop the ellipsis, so UI tests find "appMenu-Settings".
        #expect(all.first { $0.action == .settings }?.id == "Settings")
        #expect(Set(all.map(\.id)).count == all.count)
    }

    @Test func header() {
        #expect(PanelMenuModel.header(version: "0.1.0", build: "42") == "FSearch v0.1.0 (42)")
        #expect(PanelMenuModel.header(version: "0.1.0", build: "") == "FSearch v0.1.0")
        #expect(PanelMenuModel.headerLabel(version: "0.1.0", build: "42") == "FSearch version 0.1.0 (42)")
        #expect(PanelMenuModel.headerLabel(version: "0.1.0", build: "") == "FSearch version 0.1.0")
    }

    @Test(arguments: [
        ("chan", ["Changelog"]), ("SET", ["Settings…"]), ("zzz", []), ("  chan ", ["Changelog"]),
        ("bug", ["Send Feedback"]), ("prefs", ["Settings…"]), ("help", ["Manual"]), ("exit", ["Quit FSearch"]),
        ("repo", ["GitHub"]), ("forum", ["Discussions"]),
    ])
    func filterMatchesTitlesAndKeywords(_ q: String, _ expected: [String]) {
        var m = PanelMenuModel()
        m.filter = q
        #expect(titles(m) == expected)
    }

    @Test func emptySectionsHide() {
        var m = PanelMenuModel()
        m.filter = "git"
        #expect(titles(m) == ["GitHub"])
        #expect(m.visibleSections.map(\.title) == ["Community"])
        m.filter = "zzz"
        #expect(m.visibleSections.isEmpty)
        #expect(m.isEmpty)
        #expect(m.selected == nil)
    }

    @Test func movingWrapsAndSkipsHeaders() {
        var m = PanelMenuModel()
        #expect(m.selected?.action == .sendFeedback)
        _ = m.handle(.up)
        #expect(m.selected?.action == .quit)
        _ = m.handle(.down)
        #expect(m.selected?.action == .sendFeedback)
        for _ in 0..<6 { _ = m.handle(.down) }
        // Past the divider and the "Community" header, straight to the next row.
        #expect(m.selected?.action == .github)
        m.filter = "zzz"
        _ = m.handle(.down)
        #expect(m.selection == 0 && m.selected == nil)
    }

    @Test func filterResetsSelectionToTheFirstMatch() {
        var m = PanelMenuModel()
        _ = m.handle(.down)
        _ = m.handle(.down)
        m.filter = "s"
        #expect(m.selection == 0)
        #expect(m.selected == m.visibleItems.first)
    }

    @Test func selectionClamps() {
        var m = PanelMenuModel()
        m.selection = 99
        #expect(m.selected?.action == .quit)
        m.selection = -3
        #expect(m.selected?.action == .sendFeedback)
        m.select(.discussions)
        #expect(m.selected?.action == .discussions)
        m.filter = "chan"
        m.select(.quit)  // not showing: no change
        #expect(m.selected?.action == .changelog)
    }

    @Test func enterRunsTheSelectedRowAndCloses() {
        var m = PanelMenuModel()
        m.open()
        m.filter = "chan"
        #expect(m.handle(.enter) == .run(.changelog))
        #expect(!m.isOpen)
        m.open()
        #expect(m.filter.isEmpty && m.selection == 0)
        m.filter = "zzz"
        #expect(m.handle(.enter) == .none)
        #expect(m.isOpen)
    }

    @Test func escapeClearsTheFilterThenCloses() {
        var m = PanelMenuModel()
        m.open()
        m.filter = "chan"
        #expect(m.handle(.escape) == .none)
        #expect(m.filter.isEmpty && m.isOpen)
        #expect(m.handle(.escape) == .close)
        #expect(!m.isOpen)
    }

    @Test func theMenuKeyTogglesAndOtherKeysDoNothing() {
        var m = PanelMenuModel()
        m.toggle()
        #expect(m.isOpen)
        #expect(m.handle(.cmdK) == .none)
        #expect(m.handle(.cmdY) == .none)
        #expect(m.handle(.cmdDigit(1)) == .none)
        #expect(m.handle(.cmdEnter) == .none)
        #expect(m.isOpen)
        #expect(m.handle(.appMenu) == .close)
        #expect(!m.isOpen)
        m.toggle()
        m.filter = "x"
        m.toggle()
        #expect(!m.isOpen)
        m.toggle()
        #expect(m.filter.isEmpty)
    }

    @Test func chooseRunsAShowingRowAndCloses() {
        var m = PanelMenuModel()
        m.open()
        #expect(m.choose(.about) == .run(.about))
        #expect(!m.isOpen)
        m.open()
        m.filter = "chan"
        #expect(m.choose(.quit) == .none)
        #expect(m.isOpen)
    }

    @Test func theMenuKeyNeverWaitsForResults() {
        #expect(!PanelKey.appMenu.actsOnResults)
        var s = PanelState(query: "x", selection: 0, count: 3)
        #expect(s.reduce(.appMenu) == .none)
        #expect(s == PanelState(query: "x", selection: 0, count: 3))
    }
}
