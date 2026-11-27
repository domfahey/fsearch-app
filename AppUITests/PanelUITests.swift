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
        let first = try waitForClipboard(matching: { $0.hasSuffix("plover-one.txt") || $0.hasSuffix("plover-two.txt") })
        try press(.downArrow)
        try press("c", [.command, .shift])
        let second = try waitForClipboard(matching: { $0 != first && ($0.hasSuffix("plover-one.txt") || $0.hasSuffix("plover-two.txt")) })
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Set([first, second].map { ($0 as NSString).lastPathComponent }), ["plover-one.txt", "plover-two.txt"])
        try press(.upArrow)
        try press("c", [.command, .shift])
        _ = try waitForClipboard(matching: { $0 == first })
        // ⌃N / ⌃P move it too.
        try press("n", .control)
        try press("c", [.command, .shift])
        _ = try waitForClipboard(matching: { $0 == second })
        try press("p", .control)
        try press("c", [.command, .shift])
        _ = try waitForClipboard(matching: { $0 == first })
    }

    func testSearchInsideFilesByKeyboard() throws {
        try launch()
        try enterContentMode("quokkaneedle")
        waitFor(text("notes.md"))
        waitFor(text(containing: "the quokkaneedle line"))
        XCTAssertTrue(text(containing: "2 ·").exists, "the line number is shown")
        // Default app is chosen in test mode (no line-jumping editor), so the footer says "Open".
        XCTAssertTrue(text("Open").exists)
    }

    func testFindDefinitions() throws {
        try launch()
        try search("kestrelHandler")
        waitFor(text("Find definitions"))
        XCTAssertFalse(text("Files").exists, "a file matched")
        try press(.downArrow)
        try pressReturnOnFallback("fallback-symbols")
        waitFor(modeChip("Definitions"))
        waitFor(text("kestrel.swift"))
        waitFor(text(containing: "func kestrelHandler"))
    }

    func testEscapeClearsThenDropsTheChipThenHides() throws {
        try launch()
        try enterContentMode("quokkaneedle")
        try press(.escape)
        waitUntil(5, "query cleared") { (self.field.value as? String ?? "") == "" }
        XCTAssertTrue(modeChip("Inside files").exists, "the chip stays after the first Esc")
        try press(.escape)
        waitForAbsence(modeChip("Inside files"), 5)
        try press(.escape)
        waitForAbsence(field, 5, "the third Esc hides the panel")
    }

    func testBackspaceOnEmptyDropsTheChip() throws {
        try launch()
        try enterContentMode("quokkaneedle")
        try search("")
        waitUntil(5, "query cleared") { (self.field.value as? String ?? "") == "" }
        XCTAssertTrue(modeChip("Inside files").exists, tree())
        try press(.delete)
        waitForAbsence(modeChip("Inside files"), 5)
        XCTAssertTrue(field.exists)
    }

    func testCopyPathKeepsSpacesAndEmoji() throws {
        try launch()
        try search("heronfile")
        waitFor(text("heronfile.txt"))
        try press("c", [.command, .shift])
        _ = try waitForClipboard(matching: { $0.hasSuffix("/proj/heronfile.txt") })
        // A query only the emoji file matches.
        try search("zq wv")
        waitFor(text("🏡 zq wv.txt"))
        try press("c", [.command, .shift])
        _ = try waitForClipboard(matching: { $0.hasSuffix("/proj/🏡 zq wv.txt") })
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
        waitForAbsence(preview, 10, tree())
        // The field gets the keyboard back.
        waitUntil(5, "field focused") { self.field.value(forKey: "hasKeyboardFocus") as? Bool == true }
    }

    /// In Quick Look, ↓ moves the launcher's selection; ⌘Y still closes the preview.
    func testQuickLookArrowMovesTheSelection() throws {
        try launch()
        try search("plover")
        waitFor(text("plover-one.txt"))
        waitFor(text("plover-two.txt"))
        try press("c", [.command, .shift])
        let first = try waitForClipboard(matching: { $0.hasSuffix("plover-one.txt") || $0.hasSuffix("plover-two.txt") })
        let preview = app.windows["Quick Look"]
        try press("y", .command)
        waitFor(preview, 10)
        try pressInApp(.downArrow)
        try pressInApp("y", .command)
        waitForAbsence(preview, 10, tree())
        waitUntil(5, "field focused") { self.field.value(forKey: "hasKeyboardFocus") as? Bool == true }
        // The selection moved while the preview was up.
        try press("c", [.command, .shift])
        let second = try waitForClipboard(matching: { $0 != first && ($0.hasSuffix("plover-one.txt") || $0.hasSuffix("plover-two.txt")) })
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(Set([first, second].map { ($0 as NSString).lastPathComponent }), ["plover-one.txt", "plover-two.txt"])
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
        waitForAbsence(app.menuItems["Move to Trash"], 5)
    }

    /// ⌘/ opens the FSearch menu; its field filters the rows, and Esc clears, then closes, with the panel still up.
    func testAppMenuFiltersAndEscapeCloses() throws {
        try launch()
        try press("/", .command)
        waitFor(element("appMenu-Settings"), 10)
        XCTAssertTrue(element("appMenuButton").exists)
        // The menu's field has the keyboard now, not the search field.
        let menuField = element("appMenuField")
        waitUntil(5, "menu field focused") { menuField.value(forKey: "hasKeyboardFocus") as? Bool == true }
        try requireFocus(field: false)
        menuField.typeText("chan")
        waitFor(element("appMenu-Changelog"), 5)
        waitForAbsence(element("appMenu-Settings"), 5, tree())
        XCTAssertEqual(field.value as? String ?? "", "", "typing went to the menu, not the search")
        try pressInApp(.escape)
        waitFor(element("appMenu-Settings"), 5)
        try pressInApp(.escape)
        waitForAbsence(element("appMenu-Changelog"), 5)
        XCTAssertTrue(field.exists, "the panel stays up")
        // The search field has the keyboard again: typing edits the query.
        waitUntil(5, "search field focused") { self.field.value(forKey: "hasKeyboardFocus") as? Bool == true }
        try type("h")
        waitUntil(5, "typed into the search") { (self.field.value as? String ?? "") == "h" }

        // Clicking the footer gear also opens the menu with the filter focused, and ↵ runs the filtered item.
        try click(element("appMenuButton"))
        waitFor(element("appMenu-Settings"), 10)
        waitUntil(5, "menu field focused after gear click") { menuField.value(forKey: "hasKeyboardFocus") as? Bool == true }
        menuField.typeText("set")
        waitForAbsence(element("appMenu-Changelog"), 5)
        try pressInApp(.return)
        waitFor(app.checkBoxes["Debug mode"], 10)
        waitForAbsence(field, 5, "running Settings from the menu hides the panel")
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
        waitForAbsence(text("notes.md"), 5)
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
        let item = statusItem
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
        waitForAbsence(field, 5, "↵ puts the launcher away")
        app.terminate()

        try launch()
        try search("heronfile")
        waitFor(text("heronfile.txt"))
        try press(.return, .command)
        waitUntil(5, "reveal recorded") { self.recordedActions.contains("reveal \(file)") }
    }

    /// ↵ on a launchable script reveals it in Finder instead of launching it, while ⌘K → Open explicitly launches it.
    func testLaunchableRevealsOnReturnInsteadOfOpening() throws {
        try launch()
        try search("osprey")
        waitFor(text("osprey-script.command"))
        waitFor(element("launchHint"), 5)
        XCTAssertTrue(text("Reveal in Finder").exists)
        let before = recordedActions.count
        try press(.return)
        let script = fixtureRoot + "/proj/osprey-script.command"
        waitUntil(5, "reveal recorded for launchable") {
            self.recordedActions.dropFirst(before).contains("reveal \(script)")
        }
        XCTAssertFalse(recordedActions.dropFirst(before).contains("open \(script)"), "launchable must reveal, not open")
        waitForAbsence(field, 5, "↵ puts the launcher away")

        // Reopen and explicitly launch via ⌘K → Open (recorded safely by TestModeWorkspace).
        reopenPanel()
        waitFor(field, 10)
        waitFor(text("osprey-script.command"))
        let beforeOpen = recordedActions.count
        try press("k", .command)
        let menu = app.menus.containing(.menuItem, identifier: "Open").firstMatch
        waitFor(menu.menuItems["Open"], 10)
        try click(menu.menuItems["Open"])
        waitUntil(5, "⌘K → Open recorded launch") {
            self.recordedActions.dropFirst(beforeOpen).contains("open \(script)")
        }
        waitForAbsence(field, 5, "⌘K → Open puts the launcher away")
    }

    /// ⌘2 opens the second file row regardless of selection, and reopening the panel shows it under Recent.
    func testCommandNumberOpensRowAndShowsInRecents() throws {
        try launch()
        try search("plover")
        waitFor(text("plover-one.txt"))
        waitFor(text("plover-two.txt"))
        try press("c", [.command, .shift])
        let first = try waitForClipboard(matching: { $0.hasSuffix("plover-one.txt") || $0.hasSuffix("plover-two.txt") })
        try press(.downArrow)
        try press("c", [.command, .shift])
        let second = try waitForClipboard(matching: {
            $0 != first && ($0.hasSuffix("plover-one.txt") || $0.hasSuffix("plover-two.txt"))
        })
        try press(.upArrow)
        let before = recordedActions.count
        try press("2", .command)
        waitUntil(5, "⌘2 opened second row") { self.recordedActions.dropFirst(before).contains("open \(second)") }
        XCTAssertFalse(recordedActions.dropFirst(before).contains("open \(first)"))
        waitForAbsence(field, 5, "⌘2 puts the launcher away")

        // Reopen via the single-instance reopen handoff (resumes "plover" within 60 s), clear with Esc, and verify Recent.
        reopenPanel()
        waitFor(field, 10)
        waitUntil(5, "resumed query") { (self.field.value as? String ?? "") == "plover" }
        try press(.escape)
        waitUntil(5, "query cleared to show recents") { (self.field.value as? String ?? "") == "" }
        waitFor(text("Recent"), 10)
        waitFor(text((second as NSString).lastPathComponent), 10)
    }

    /// Toggling Debug mode on and off in Settings updates the panel indicator, timing footer, menu-bar items, and search log.
    func testDebugModeInSettingsCreatesAndDeletesLog() throws {
        try launch(debugMode: false)
        XCTAssertFalse(element("debugModeIndicator").exists)

        // Hide the floating panel first so it doesn't sit over the Settings window, then enable Debug mode.
        try press(.escape)
        waitForAbsence(field, 5)
        try pressInApp(",", .command)
        let toggle = app.checkBoxes["Debug mode"]
        waitFor(toggle, 10)
        try click(toggle)
        waitUntil(5, "debug mode enabled") { toggle.value as? Int == 1 }
        try pressInApp("w", .command)

        // Reopen the panel: shows the orange debug dot, timing footer, and logs the search into temp HOME.
        reopenPanel()
        waitFor(field, 10)
        waitFor(element("debugModeIndicator"), 5)
        try search("heronfile")
        waitFor(text("heronfile.txt"))
        let footer = app.staticTexts.matching(NSPredicate(format: "value CONTAINS ' ms · ' AND value ENDSWITH ' results'")).firstMatch
        waitFor(footer, 10)
        waitUntil(5, "debug search log written") { FileManager.default.fileExists(atPath: self.debugSearchLogURL.path) }

        // Menu bar lists Index Details… and Search Log… while debug mode is on.
        let item = statusItem
        waitFor(item, 10)
        let menu = item.descendants(matching: .menuItem)
        waitFor(menu["Index Details…"], 10)
        XCTAssertTrue(menu["Search Log…"].exists)
        XCTAssertTrue(menu["Turn Off Debug Mode"].exists)

        // Clear and hide the panel, then turn Debug mode off in Settings: deletes the search log and debug UI.
        try press(.escape)
        waitUntil(5, "query cleared") { (self.field.value as? String ?? "") == "" }
        try press(.escape)
        waitForAbsence(field, 5)
        try pressInApp(",", .command)
        waitFor(toggle, 10)
        try click(toggle)
        waitUntil(5, "debug mode disabled") { toggle.value as? Int == 0 }
        try pressInApp("w", .command)

        waitUntil(5, "debug search log deleted") { !FileManager.default.fileExists(atPath: self.debugSearchLogURL.path) }
        waitForAbsence(menu["Index Details…"], 5)
        reopenPanel()
        waitFor(field, 10)
        XCTAssertFalse(element("debugModeIndicator").exists)
    }

    /// `fsearch://search?q=…&mode=…` opens the hidden panel pre-filled and updates it when already open.
    func testURLSchemeOpensPanelWithQueryAndMode() async throws {
        try launch()
        try press(.escape)
        waitForAbsence(field, 5, "Esc hides the empty panel")

        let symURL = try XCTUnwrap(URL(string: "fsearch://search?q=kestrelHandler&mode=symbols"))
        try await openURLInTestApp(symURL)
        waitFor(field, 10)
        waitUntil(5, "symbol query prefilled") { (self.field.value as? String ?? "") == "kestrelHandler" }
        waitFor(modeChip("Definitions"), 10)
        waitFor(text("kestrel.swift"), 10)
        waitFor(text(containing: "func kestrelHandler"), 10)

        let contentURL = try XCTUnwrap(URL(string: "fsearch://search?q=quokkaneedle&mode=content"))
        try await openURLInTestApp(contentURL)
        waitUntil(5, "content query replaced") { (self.field.value as? String ?? "") == "quokkaneedle" }
        waitFor(modeChip("Inside files"), 10)
        waitFor(text("notes.md"), 10)
        waitFor(text(containing: "the quokkaneedle line"), 10)
    }

    /// Right after an external `fsearch://` open, ↵ is ignored for 0.5 s; pressing ↵ after the guard window opens the file.
    func testExternalOpenGuardsImmediateReturn() async throws {
        try launch()
        try press(.escape)
        waitForAbsence(field, 5)

        let before = recordedActions.count
        let file = fixtureRoot + "/proj/heronfile.txt"
        let opened = ContinuousClock.now
        let url = try XCTUnwrap(URL(string: "fsearch://search?q=heronfile"))
        try await openURLInTestApp(url)
        waitFor(field, 5)
        waitUntil(5, "field focused after external open") { self.field.value(forKey: "hasKeyboardFocus") as? Bool == true }
        let elapsedBeforeReturn = ContinuousClock.now - opened
        field.typeKey(.return, modifierFlags: [])
        XCTAssertLessThan(
            elapsedBeforeReturn, .milliseconds(450),
            "test setup exceeded the 0.5 s external-open guard window (\(elapsedBeforeReturn))")

        // Results land, yet the guarded ↵ must not have opened the file or hidden the panel.
        waitFor(text("heronfile.txt"), 10)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertTrue(field.exists, "guarded ↵ must keep the panel open")
        XCTAssertFalse(
            recordedActions.dropFirst(before).contains("open \(file)"),
            "↵ within 0.5 s of an external open must be ignored")

        // Once the 0.5 s guard expires, ↵ opens normally.
        try press(.return)
        waitUntil(5, "post-guard ↵ opened file") { self.recordedActions.dropFirst(before).contains("open \(file)") }
        waitForAbsence(field, 5)
    }

    /// Typing forward into a half-typed filter (`type:code,`, `type:code,d`) keeps current results on screen without an error.
    func testHalfTypedFilterKeepsCurrentResults() throws {
        try launch()
        try search("kestrel type:code")
        waitFor(text("kestrel.swift"))

        try type(",")
        waitUntil(5, "trailing comma filter in field") { (self.field.value as? String ?? "") == "kestrel type:code," }
        assertStaysAbsent(text("queryError"), 1)
        XCTAssertTrue(text("kestrel.swift").exists, "current results stay up for half-typed type:code,")

        try type("d")
        waitUntil(5, "prefix type filter in field") { (self.field.value as? String ?? "") == "kestrel type:code,d" }
        assertStaysAbsent(text("queryError"), 1)
        XCTAssertTrue(text("kestrel.swift").exists, "current results stay up for half-typed type:code,d")

        try type("oc")
        waitUntil(5, "completed filter in field") { (self.field.value as? String ?? "") == "kestrel type:code,doc" }
        waitFor(text("kestrel.swift"), 5)
        XCTAssertFalse(text("queryError").exists)
    }

    /// Clicking a row selects it, and double-clicking a row opens it and hides the panel.
    func testMouseClickSelectsAndDoubleClickOpensRow() throws {
        try launch()
        try search("plover")
        waitFor(text("plover-one.txt"))
        waitFor(text("plover-two.txt"))

        try press("c", [.command, .shift])
        let first = try waitForClipboard(matching: { $0.hasSuffix("plover-one.txt") || $0.hasSuffix("plover-two.txt") })
        let otherName = first.hasSuffix("plover-one.txt") ? "plover-two.txt" : "plover-one.txt"
        let otherRow = text(otherName)
        let otherGroup = element("result-\(fixtureRoot)/proj/duo/\(otherName)")

        try click(otherRow)
        waitUntil(5, "clicked row selected") { otherGroup.isSelected }
        try press("c", [.command, .shift])
        let second = try waitForClipboard(matching: { $0.hasSuffix("/" + otherName) })

        let before = recordedActions.count
        try requireFocus(field: false)
        otherRow.doubleClick()
        waitUntil(5, "double-click opened row") { self.recordedActions.dropFirst(before).contains("open \(second)") }
        waitForAbsence(field, 5, "double-click hides the panel")
    }

    /// Composed accented queries (`café`) match NFD filenames on disk, and inline `grep:` returns line hits without a chip.
    func testAccentedFilenameAndInlineGrepQuery() throws {
        try launch()
        try search("café")
        waitFor(text(containing: "-note.txt"), 10)
        try press("c", [.command, .shift])
        let copied = try waitForClipboard(matching: { $0.hasSuffix("-note.txt") })
        XCTAssertTrue((copied as NSString).lastPathComponent.precomposedStringWithCanonicalMapping == "café-note.txt")

        try search("grep:quokkaneedle")
        waitFor(text("notes.md"), 10)
        waitFor(text(containing: "the quokkaneedle line"), 10)
        XCTAssertFalse(modeChip("Inside files").exists, "inline grep: runs without showing the mode chip")
    }
}
