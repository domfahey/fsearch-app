import Testing
@testable import FSearchKit

@Suite struct MenuActionTests {
    @Test func leavingActionsHideThePanel() {
        let hiding = MenuAction.allCases.filter(\.hidesPanel)
        #expect(Set(hiding) == [.open, .openWith, .reveal, .openTerminal])
    }

    @Test func openingRecordsARecent() {
        let recording = MenuAction.allCases.filter(\.recordsRecent)
        #expect(Set(recording) == [.open, .openWith])
    }

    @Test func copyQuickLookAndTrashKeepThePanel() {
        for a in [MenuAction.copyPath, .copyFile, .quickLook, .trash] { #expect(!a.hidesPanel) }
    }
}

@Suite struct MenuActionErrorTests {
    @Test func anErrorKeepsThePanelUpSoItCanBeRead() {
        #expect(MenuAction.openTerminal.hidesPanel(errored: false))
        #expect(!MenuAction.openTerminal.hidesPanel(errored: true))
        #expect(!MenuAction.copyPath.hidesPanel(errored: false))
    }
}
