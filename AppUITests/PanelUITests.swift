import AppKit
import XCTest

/// End-to-end panel behaviour against the real daemon and the fixtures that
/// scripts/ui-smoke.sh creates. In test mode the app's workspace only records
/// actions (open, reveal, Open With, Terminal, Trash), so ↵ and ⌘↵ on a file
/// row are safe: nothing leaves the app. Menu items other than Copy Path are
/// still never clicked.
@MainActor
final class PanelUITests: PanelUITestCase {
    func testNameSearchShowsResult() throws {
        try launch()
        try search("heronfile")
        waitFor(text("heronfile.txt"))
        XCTAssertTrue(text("Files").exists)
    }

    func testArrowKeysMoveTheSelection() throws {
        try launch()
        try search("plover")
        waitFor(text("plover-one.txt"))
        waitFor(text("plover-two.txt"))
        // The copied path follows the selection.
        try press("c", [.command, .shift])
        let first = try XCTUnwrap(clipboard)
        try press(.downArrow)
        try press("c", [.command, .shift])
        let second = try XCTUnwrap(clipboard)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Set([first, second].map { ($0 as NSString).lastPathComponent }), ["plover-one.txt", "plover-two.txt"])
        try press(.upArrow)
        try press("c", [.command, .shift])
        XCTAssertEqual(clipboard, first)
        // ⌃N / ⌃P move it too.
        try press("n", .control)
        try press("c", [.command, .shift])
        XCTAssertEqual(clipboard, second)
        try press("p", .control)
        try press("c", [.command, .shift])
        XCTAssertEqual(clipboard, first)
    }

    func testSearchInsideFilesByKeyboard() throws {
        try launch()
        try enterContentMode("quokkaneedle")
        waitFor(text("notes.md"))
        waitFor(text(containing: "the quokkaneedle line"))
        XCTAssertTrue(text(containing: "2 ·").exists, "the line number is shown")
        XCTAssertTrue(text("Open at line").exists)
    }

    func testFindDefinitions() throws {
        try launch()
        try search("kestrelHandler")
        waitFor(text("Find definitions"))
        XCTAssertFalse(text("Files").exists, "a file matched")
        try press(.downArrow)
        try pressReturnOnFallback("fallback-symbols")
        waitFor(text("Definitions"))
        waitFor(text("kestrel.swift"))
        waitFor(text(containing: "func kestrelHandler"))
    }

    func testEscapeClearsThenDropsTheChipThenHides() throws {
        try launch()
        try enterContentMode("quokkaneedle")
        try press(.escape)
        waitUntil(5, "query cleared") { (self.field.value as? String ?? "") == "" }
        XCTAssertTrue(text("Inside files").exists, "the chip stays after the first Esc")
        try press(.escape)
        XCTAssertTrue(text("Inside files").waitForNonExistence(timeout: 5))
        try press(.escape)
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "the third Esc hides the panel")
    }

    func testBackspaceOnEmptyDropsTheChip() throws {
        try launch()
        try enterContentMode("quokkaneedle")
        try search("")
        waitUntil(5, "query cleared") { (self.field.value as? String ?? "") == "" }
        XCTAssertTrue(text("Inside files").exists, tree())
        try press(.delete)
        XCTAssertTrue(text("Inside files").waitForNonExistence(timeout: 5))
        XCTAssertTrue(field.exists)
    }

    func testCopyPathKeepsSpacesAndEmoji() throws {
        try launch()
        try search("heronfile")
        waitFor(text("heronfile.txt"))
        try press("c", [.command, .shift])
        XCTAssertEqual(clipboard?.hasSuffix("/proj/heronfile.txt"), true)
        // A query only the emoji file matches.
        try search("zq wv")
        waitFor(text("🏡 zq wv.txt"))
        try press("c", [.command, .shift])
        XCTAssertEqual(clipboard?.hasSuffix("/proj/🏡 zq wv.txt"), true)
    }

    func testQuickLookOpensAndCloses() throws {
        try launch()
        try search("heronfile")
        waitFor(text("heronfile.txt"))
        // The Quick Look panel specifically, not just any new window.
        let preview = app.windows["Quick Look"]
        XCTAssertFalse(preview.exists)
        try press("y", .command)
        waitFor(preview, 10)
        try pressInApp("y", .command)
        XCTAssertTrue(preview.waitForNonExistence(timeout: 10), tree())
        // The field gets the keyboard back.
        waitUntil(5, "field focused") { self.field.value(forKey: "hasKeyboardFocus") as? Bool == true }
    }

    func testActionsMenuListsItsItems() throws {
        try launch()
        try search("heronfile")
        waitFor(text("heronfile.txt"))
        try press("k", .command)
        let items = [
            "Open", "Open With", "Reveal in Finder", "Quick Look", "Copy Path", "Copy File", "Open Folder in Terminal", "Move to Trash",
        ]
        // The ⌘K pop-up itself, not the app's main menu or the menu-bar item's.
        let menu = app.menus.containing(.menuItem, identifier: "Copy Path").firstMatch
        waitFor(menu.menuItems["Copy Path"], 10)
        for i in items { XCTAssertTrue(menu.menuItems[i].exists, "missing \(i)") }
        // A .txt file has apps to open it with (TextEdit at least).
        XCTAssertTrue(menu.menuItems["Open With"].isEnabled)
        // Copy Path is the one item safe to run here.
        try click(menu.menuItems["Copy Path"])
        waitUntil(5, "copied") { self.clipboard?.hasSuffix("/proj/heronfile.txt") == true }
        XCTAssertTrue(field.exists, "Copy Path keeps the launcher up")
        // Esc dismisses the menu without acting.
        try press("k", .command)
        waitFor(app.menuItems["Move to Trash"], 10)
        try pressInApp(.escape)
        XCTAssertTrue(app.menuItems["Move to Trash"].waitForNonExistence(timeout: 5))
    }

    func testQuestionMarkShowsTheCheatSheet() throws {
        try launch()
        try search("?")
        waitFor(text("Query syntax"), 5)
        try search("heronfile")
        waitFor(text("heronfile.txt"))
        XCTAssertFalse(text("Query syntax").exists)
    }

    func testBadRegexShowsItsErrorUnderTheField() throws {
        try launch()
        try search("re:(")
        waitFor(text("queryError"), 10)
        XCTAssertEqual(app.staticTexts.matching(identifier: "queryError").count, 1, "one error line")
        try search("heronfile")
        waitFor(text("heronfile.txt"))
        XCTAssertFalse(text("queryError").exists)
    }

    func testFilterOnlyContentQueryStaysIdle() throws {
        try launch()
        try enterContentMode("quokkaneedle")
        waitFor(text("notes.md"))
        // Only a filter: nothing is searched, no error, no results.
        try search("ext:md")
        XCTAssertTrue(text("notes.md").waitForNonExistence(timeout: 5))
        assertStaysAbsent(text("queryError"))
        // Adding a pattern searches again.
        try search("ext:md quokkaneedle")
        waitFor(text("notes.md"))
    }

    /// Debug mode shows the timing footer; the script checks the search log
    /// landed in the temp HOME and the real ~/Library/Logs was left alone.
    func testDebugModeShowsTimingAndLogsInTempHome() throws {
        try launch(debugMode: true)
        try search("heronfile")
        waitFor(text("heronfile.txt"))
        let footer = app.staticTexts.matching(NSPredicate(format: "value CONTAINS ' ms · ' AND value ENDSWITH ' results'")).firstMatch
        waitFor(footer, 10)
    }

    func testNoTimingFooterWithoutDebugMode() throws {
        try launch()
        try search("heronfile")
        waitFor(text("heronfile.txt"))
        XCTAssertFalse(
            app.staticTexts.matching(NSPredicate(format: "value CONTAINS ' ms · ' OR label CONTAINS ' ms · '")).firstMatch.exists)
    }

    func testSettingsWindowOpens() throws {
        try launch()
        // ⌘, reaches the app's (hidden) main menu while the panel is key.
        try pressInApp(",", .command)
        waitFor(app.checkBoxes["Debug mode"], 10)
        XCTAssertTrue(text("Debug mode shows index details and records searches on this Mac only (last 10,000).").exists)
        XCTAssertTrue(text("Open content results in:").exists)
    }

    /// The panel's "FSearch Settings" command row opens the Settings window
    /// (showSettingsWindow: is a no-op on macOS 14+). No fixture is named
    /// "prefs", so the command is the first, selected row.
    func testSettingsCommandOpensSettings() throws {
        try launch()
        try search("prefs")
        waitFor(text("FSearch Settings"))
        try pressReturnOnFallback("command-FSearch Settings")
        waitFor(app.checkBoxes["Debug mode"], 10)
        XCTAssertTrue(text("Open content results in:").exists)
    }

    func testMenuBarItemListsTheMenu() throws {
        try launch()
        let item = app.statusItems["FSearch"]
        waitFor(item, 10)
        try click(item)
        let menu = item.descendants(matching: .menuItem)
        waitFor(menu["Search…"], 10)
        XCTAssertTrue(menu["Turn On Debug Mode"].exists)
        XCTAssertTrue(menu["Settings…"].exists)
        XCTAssertTrue(menu["Quit FSearch"].exists)
        XCTAssertFalse(menu["Index Details…"].exists, "debug items only in debug mode")
        try pressInApp(.escape)
    }

    /// ↵ opens and ⌘↵ reveals the selected file; in test mode both are only
    /// recorded by the app's workspace, never performed.
    func testReturnAndCommandReturnAreRecordedNotPerformed() throws {
        try launch()
        try search("heronfile")
        waitFor(text("heronfile.txt"))
        try press(.return)
        let file = fixtureRoot + "/proj/heronfile.txt"
        waitUntil(5, "open recorded") { self.recordedActions.contains("open \(file)") }
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "↵ puts the launcher away")
        app.terminate()

        try launch()
        try search("heronfile")
        waitFor(text("heronfile.txt"))
        try press(.return, .command)
        waitUntil(5, "reveal recorded") { self.recordedActions.contains("reveal \(file)") }
    }
}
