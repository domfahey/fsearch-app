import AppKit
import XCTest

/// End-to-end panel behaviour against the real daemon and the fixtures that
/// scripts/ui-smoke.sh creates. No test presses ↵/⌘↵ on a file row or clicks
/// Open, Open With, Reveal, Terminal or Trash: nothing leaves the app.
@MainActor
final class PanelUITests: PanelUITestCase {
    func testNameSearchShowsResult() throws {
        try launch()
        search("heronfile")
        waitFor(text("heronfile.txt"))
        XCTAssertTrue(text("Files").exists)
    }

    func testArrowKeysMoveTheSelection() throws {
        try launch()
        search("plover")
        waitFor(text("plover-one.txt"))
        waitFor(text("plover-two.txt"))
        // The copied path follows the selection.
        press("c", [.command, .shift])
        let first = try XCTUnwrap(clipboard)
        press(.downArrow)
        press("c", [.command, .shift])
        let second = try XCTUnwrap(clipboard)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Set([first, second].map { ($0 as NSString).lastPathComponent }), ["plover-one.txt", "plover-two.txt"])
        press(.upArrow)
        press("c", [.command, .shift])
        XCTAssertEqual(clipboard, first)
        // ⌃N / ⌃P move it too.
        press("n", .control)
        press("c", [.command, .shift])
        XCTAssertEqual(clipboard, second)
        press("p", .control)
        press("c", [.command, .shift])
        XCTAssertEqual(clipboard, first)
    }

    func testSearchInsideFilesByKeyboard() throws {
        try launch()
        enterContentMode("quokkaneedle")
        waitFor(text("notes.md"))
        waitFor(text(containing: "the quokkaneedle line"))
        XCTAssertTrue(text(containing: "2 ·").exists, "the line number is shown")
        XCTAssertTrue(text("Open at line").exists)
    }

    func testFindDefinitions() throws {
        try launch()
        search("kestrelHandler")
        waitFor(text("Find definitions"))
        XCTAssertFalse(text("Files").exists, "a file matched: not pressing ↵")
        press(.downArrow)
        press(.return)
        waitFor(text("Definitions"))
        waitFor(text("kestrel.swift"))
        waitFor(text(containing: "func kestrelHandler"))
    }

    func testEscapeClearsThenDropsTheChipThenHides() throws {
        try launch()
        enterContentMode("quokkaneedle")
        press(.escape)
        waitUntil(5, "query cleared") { (self.field.value as? String ?? "") == "" }
        XCTAssertTrue(text("Inside files").exists, "the chip stays after the first Esc")
        press(.escape)
        XCTAssertTrue(text("Inside files").waitForNonExistence(timeout: 5))
        press(.escape)
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "the third Esc hides the panel")
    }

    func testBackspaceOnEmptyDropsTheChip() throws {
        try launch()
        enterContentMode("quokkaneedle")
        search("")
        waitUntil(5, "query cleared") { (self.field.value as? String ?? "") == "" }
        XCTAssertTrue(text("Inside files").exists, tree())
        press(.delete)
        XCTAssertTrue(text("Inside files").waitForNonExistence(timeout: 5))
        XCTAssertTrue(field.exists)
    }

    func testCopyPathKeepsSpacesAndEmoji() throws {
        try launch()
        search("heronfile")
        waitFor(text("heronfile.txt"))
        press("c", [.command, .shift])
        XCTAssertEqual(clipboard?.hasSuffix("/proj/heronfile.txt"), true)
        // A query only the emoji file matches.
        search("zq wv")
        waitFor(text("🏡 zq wv.txt"))
        press("c", [.command, .shift])
        XCTAssertEqual(clipboard?.hasSuffix("/proj/🏡 zq wv.txt"), true)
    }

    func testQuickLookOpensAndCloses() throws {
        try launch()
        search("heronfile")
        waitFor(text("heronfile.txt"))
        // The Quick Look panel specifically, not just any new window.
        let preview = app.windows["Quick Look"]
        XCTAssertFalse(preview.exists)
        press("y", .command)
        waitFor(preview, 10)
        pressInApp("y", .command)
        XCTAssertTrue(preview.waitForNonExistence(timeout: 10), tree())
        // The field gets the keyboard back.
        waitUntil(5, "field focused") { self.field.value(forKey: "hasKeyboardFocus") as? Bool == true }
    }

    func testActionsMenuListsItsItems() throws {
        try launch()
        search("heronfile")
        waitFor(text("heronfile.txt"))
        press("k", .command)
        let items = ["Open", "Open With", "Reveal in Finder", "Quick Look", "Copy Path", "Copy File", "Open Folder in Terminal", "Move to Trash"]
        waitFor(app.menuItems["Copy Path"], 10)
        for i in items { XCTAssertTrue(app.menuItems[i].exists, "missing \(i)") }
        // Copy Path is the one item safe to run here.
        click(app.menuItems["Copy Path"])
        waitUntil(5, "copied") { self.clipboard?.hasSuffix("/proj/heronfile.txt") == true }
        XCTAssertTrue(field.exists, "Copy Path keeps the launcher up")
        // Esc dismisses the menu without acting.
        press("k", .command)
        waitFor(app.menuItems["Move to Trash"], 10)
        pressInApp(.escape)
        XCTAssertTrue(app.menuItems["Move to Trash"].waitForNonExistence(timeout: 5))
    }

    func testQuestionMarkShowsTheCheatSheet() throws {
        try launch()
        search("?")
        waitFor(text("Query syntax"), 5)
        search("heronfile")
        waitFor(text("heronfile.txt"))
        XCTAssertFalse(text("Query syntax").exists)
    }

    func testBadRegexShowsOneLineUnderTheField() throws {
        try launch()
        search("re:(")
        waitFor(text("queryError"), 10)
        search("heronfile")
        waitFor(text("heronfile.txt"))
        XCTAssertFalse(text("queryError").exists)
    }

    func testFilterOnlyContentQueryStaysIdle() throws {
        try launch()
        enterContentMode("quokkaneedle")
        waitFor(text("notes.md"))
        // Only a filter: nothing is searched, no error, no results.
        search("ext:md")
        XCTAssertTrue(text("notes.md").waitForNonExistence(timeout: 5))
        assertStaysAbsent(text("queryError"))
        assertStaysAbsent(text("notes.md"), 1)
        // Adding a pattern searches again.
        search("ext:md quokkaneedle")
        waitFor(text("notes.md"))
    }

    /// Debug mode shows the timing footer; the script checks the search log
    /// landed in the temp HOME and the real ~/Library/Logs was left alone.
    func testDebugModeShowsTimingAndLogsInTempHome() throws {
        try launch(debugMode: true)
        search("heronfile")
        waitFor(text("heronfile.txt"))
        let footer = app.staticTexts.matching(NSPredicate(format: "value CONTAINS ' ms · ' AND value ENDSWITH ' results'")).firstMatch
        waitFor(footer, 10)
    }

    func testNoTimingFooterWithoutDebugMode() throws {
        try launch()
        search("heronfile")
        waitFor(text("heronfile.txt"))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "value CONTAINS ' ms · ' OR label CONTAINS ' ms · '")).firstMatch.exists)
    }

    func testSettingsWindowOpens() throws {
        try launch()
        // ⌘, reaches the app's (hidden) main menu while the panel is key.
        pressInApp(",", .command)
        waitFor(app.checkBoxes["Debug mode"], 10)
        XCTAssertTrue(text("Debug mode shows index details and records searches on this Mac only (last 10,000).").exists)
        XCTAssertTrue(text("Open content results in:").exists || app.popUpButtons.firstMatch.exists)
    }

    func testMenuBarItemListsTheMenu() throws {
        try launch()
        let item = app.statusItems["FSearch"]
        waitFor(item, 10)
        click(item)
        let menu = item.descendants(matching: .menuItem)
        waitFor(menu["Search…"], 10)
        XCTAssertTrue(menu["Turn On Debug Mode"].exists)
        XCTAssertTrue(menu["Settings…"].exists)
        XCTAssertTrue(menu["Quit FSearch"].exists)
        XCTAssertFalse(menu["Index Details…"].exists, "debug items only in debug mode")
        pressInApp(.escape)
    }
}
