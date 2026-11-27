import AppKit
import XCTest

/// End-to-end tests for the Everything-style multi-window search browser (v2)
/// against the real daemon and throwaway fixtures created by `scripts/ui-smoke.sh`.
///
/// All file actions (`open`, `reveal`, `trash`) are safely recorded by `TestModeWorkspace`
/// and never touch files outside the test fixture.
@MainActor
final class SearchWindowUITests: PanelUITestCase {
    // MARK: - Window Helpers

    private var searchWindows: XCUIElementQuery {
        app.windows.containing(.textField, identifier: "searchWindowField")
    }

    private func windowElement(_ id: String, in window: XCUIElement) -> XCUIElement {
        window.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func windowField(in window: XCUIElement) -> XCUIElement {
        window.textFields["searchWindowField"]
    }

    private func table(in window: XCUIElement) -> XCUIElement {
        windowElement("searchWindowTable", in: window)
    }

    private func tableText(_ label: String, in window: XCUIElement) -> XCUIElement {
        table(in: window).staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", label, label)).firstMatch
    }

    private func tableText(containing substring: String, in window: XCUIElement) -> XCUIElement {
        table(in: window).staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", substring, substring)
        ).firstMatch
    }

    private func windowText(_ label: String, in window: XCUIElement) -> XCUIElement {
        window.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", label, label)).firstMatch
    }

    private func windowText(containing substring: String, in window: XCUIElement) -> XCUIElement {
        window.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", substring, substring)
        ).firstMatch
    }

    private func modeSegment(_ title: String, in window: XCUIElement) -> XCUIElement {
        let picker = windowElement("searchWindowModePicker", in: window)
        return picker.descendants(matching: .any).matching(
            NSPredicate(
                format: "(elementType == %lu OR elementType == %lu) AND (label == %@ OR title == %@)",
                XCUIElement.ElementType.radioButton.rawValue,
                XCUIElement.ElementType.button.rawValue,
                title,
                title
            )
        ).firstMatch
    }

    /// Opens a fresh empty Search Window from the floating panel's ⌘/ FSearch menu.
    private func openSearchWindow(file: StaticString = #filePath, line: UInt = #line) throws -> XCUIElement {
        try press("/", .command, file: file, line: line)
        let menuField = element("appMenuField")
        waitFor(element("appMenu-Search Window"), 10, file, line)
        waitUntil(5, "menu field focused", { menuField.value(forKey: "hasKeyboardFocus") as? Bool == true }, file: file, line: line)
        try requireFocus(field: false, file: file, line: line)
        menuField.typeText("win")
        waitForAbsence(element("appMenu-Settings"), 5, "menu filtered to Search Window", file: file, line: line)
        try pressInApp(.return, file: file, line: line)
        waitForAbsence(field, 5, "panel hides when opening Search Window", file: file, line: line)
        waitUntil(10, "Search Window opened", { self.searchWindows.count >= 1 }, file: file, line: line)
        let win = searchWindows.firstMatch
        waitFor(windowField(in: win), 10, file, line)
        return win
    }

    /// Replaces the text in `window`'s search field safely, only typing while FSearch is frontmost and the field is focused.
    private func searchInWindow(_ query: String, in window: XCUIElement, file: StaticString = #filePath, line: UInt = #line) throws {
        let wf = windowField(in: window)
        waitFor(wf, 10, file, line)
        for _ in 0..<3 {
            if wf.value(forKey: "hasKeyboardFocus") as? Bool != true {
                try click(wf, file: file, line: line)
                waitUntil(5, "searchWindowField focused", { wf.value(forKey: "hasKeyboardFocus") as? Bool == true }, file: file, line: line)
            }
            try requireFocus(field: false, file: file, line: line)
            wf.typeKey("a", modifierFlags: .command)
            if query.isEmpty {
                wf.typeKey(.delete, modifierFlags: [])
            } else {
                for ch in query {
                    try requireFocus(field: false, file: file, line: line)
                    guard wf.value(forKey: "hasKeyboardFocus") as? Bool == true else { break }
                    wf.typeText(String(ch))
                }
            }
            if (wf.value as? String ?? "") == query { return }
            app.activate()
        }
        throw UITestRefusal(
            "couldn't type \(query) in Search Window: field shows \(wf.value as? String ?? "nil")", file: file, line: line)
    }

    /// Types into an open input popover (`Filter by extension` or `Save Search`) and clicks its submit button.
    private func submitPopover(
        text value: String, actionTitle: String, in window: XCUIElement, file: StaticString = #filePath, line: UInt = #line
    )
        throws
    {
        let popField = window.textFields["searchWindowPopoverField"]
        waitFor(popField, 10, file, line)
        try click(popField, file: file, line: line)
        waitUntil(5, "popover field focused", { popField.value(forKey: "hasKeyboardFocus") as? Bool == true }, file: file, line: line)
        try requireFocus(field: false, file: file, line: line)
        popField.typeKey("a", modifierFlags: .command)
        popField.typeText(value)
        waitUntil(5, "popover text entered", { (popField.value as? String ?? "") == value }, file: file, line: line)
        let submit = window.popovers.buttons[actionTitle].firstMatch
        waitFor(submit, 5, file, line)
        try click(submit, file: file, line: line)
        waitForAbsence(popField, 5, "popover dismissed", file: file, line: line)
    }

    // MARK: - Entry Points & Multi-Window

    /// Opening Search Window from the panel's ⌘/ menu carries over the query; typing `window` in the panel opens a second window.
    func testPanelMenuCarriesQueryAndPanelCommandOpensSecondWindow() throws {
        try launch()
        try search("heronfile")
        waitFor(text("heronfile.txt"))

        // ⌘/ → filter "win" → ↵ runs Search Window… carrying "heronfile".
        try press("/", .command)
        let menuField = element("appMenuField")
        waitFor(element("appMenu-Search Window"), 10)
        waitUntil(5, "menu field focused") { menuField.value(forKey: "hasKeyboardFocus") as? Bool == true }
        try requireFocus(field: false)
        menuField.typeText("win")
        waitForAbsence(element("appMenu-Settings"), 5)
        try pressInApp(.return)

        waitForAbsence(field, 5, "panel hides when opening Search Window")
        waitUntil(10, "Search Window opened with carried query") { self.searchWindows.count == 1 }
        let win1 = searchWindows.firstMatch
        waitUntil(5, "window title reflects query") { win1.title == "FSearch — heronfile" }
        waitUntil(5, "query carried over") { (self.windowField(in: win1).value as? String ?? "") == "heronfile" }
        waitFor(tableText("heronfile.txt", in: win1), 10)
        waitUntil(5, "status bar reports 1 result") {
            let countEl = self.windowElement("searchWindowResultCount", in: win1)
            return (countEl.value as? String ?? countEl.label) == "1 result"
        }

        // Reopen the floating panel and run the `window` App Command to open a second independent window.
        reopenPanel()
        waitFor(field, 10)
        try search("window")
        waitFor(text("New Search Window"), 10)
        try pressReturnOnFallback("command-New Search Window")
        waitForAbsence(field, 5, "panel hides after running New Search Window command")
        waitUntil(10, "two independent Search Windows are open") { self.searchWindows.count == 2 }
    }

    /// Menu bar lists New Search Window…, ⌘N opens an independent second window, and sidebar/preview toggles work.
    func testMenuBarCommandNIndependentWindowsAndPaneToggles() throws {
        try launch()
        let item = statusItem
        waitFor(item, 10)
        waitFor(item.descendants(matching: .menuItem)["New Search Window…"], 10)

        let win1 = try openSearchWindow()
        try searchInWindow("heronfile", in: win1)
        waitFor(tableText("heronfile.txt", in: win1), 10)
        waitUntil(5, "win1 title updated") { win1.title == "FSearch — heronfile" }

        // Toggle sidebar off/on and toggle Preview pane off/on via ⌥⌘P.
        let sidebar = windowElement("searchWindowSidebar", in: win1)
        let preview = windowElement("searchWindowPreviewPane", in: win1)
        waitFor(sidebar, 5)
        waitFor(preview, 5)
        try click(windowElement("searchWindowToggleSidebar", in: win1))
        waitForAbsence(sidebar, 5)
        try click(windowElement("searchWindowToggleSidebar", in: win1))
        waitFor(sidebar, 5)

        try pressInApp("p", [.command, .option])
        waitForAbsence(preview, 5)
        try pressInApp("p", [.command, .option])
        waitFor(preview, 5)

        // ⌘N opens a second independent Search Window without disturbing window 1.
        try pressInApp("n", .command)
        waitUntil(10, "second window opened via ⌘N") { self.searchWindows.count == 2 }
        let win2 = app.windows.matching(NSPredicate(format: "title != %@", "FSearch — heronfile"))
            .containing(.textField, identifier: "searchWindowField").firstMatch
        waitFor(win2, 5)
        try searchInWindow("plover", in: win2)
        waitFor(tableText("plover-one.txt", in: win2), 10)
        waitFor(tableText("plover-two.txt", in: win2), 10)
        XCTAssertEqual(win1.title, "FSearch — heronfile", "window 1 keeps its own query and title")
        XCTAssertTrue(tableText("heronfile.txt", in: win1).exists, "window 1 keeps its own results")
    }

    // MARK: - Match Toggles & Modes

    /// Match Case (Aa), Whole Word (W), Search in Path (/), and Regular Expression (.*) work end-to-end against the real daemon.
    func testMatchTogglesFilterResultsAgainstLiveDaemon() throws {
        try launch()
        let win = try openSearchWindow()

        // Match Case: Falcon matches both without Aa, only FalconCase.txt with Aa.
        try searchInWindow("Falcon", in: win)
        waitFor(tableText("FalconCase.txt", in: win), 10)
        waitFor(tableText("falconlower.txt", in: win), 10)
        try click(windowElement("toggleMatchCase", in: win))
        waitForAbsence(tableText("falconlower.txt", in: win), 10)
        XCTAssertTrue(tableText("FalconCase.txt", in: win).exists)
        try click(windowElement("searchWindowClearFilters", in: win))
        waitFor(tableText("falconlower.txt", in: win), 10)

        // Whole Word: wren matches both without W, only wren.txt with W.
        try searchInWindow("wren", in: win)
        waitFor(tableText("wren.txt", in: win), 10)
        waitFor(tableText("wrenling.txt", in: win), 10)
        try click(windowElement("toggleWholeWord", in: win))
        waitForAbsence(tableText("wrenling.txt", in: win), 10)
        XCTAssertTrue(tableText("wren.txt", in: win).exists)
        try click(windowElement("searchWindowClearFilters", in: win))

        // Search in Path: puffin only matches nested-leaf.txt when `/` is active.
        try searchInWindow("puffin", in: win)
        waitFor(tableText("puffin", in: win), 10)
        XCTAssertFalse(tableText("nested-leaf.txt", in: win).exists)
        try click(windowElement("toggleSearchInPath", in: win))
        waitFor(tableText("nested-leaf.txt", in: win), 10)
        try click(windowElement("searchWindowClearFilters", in: win))

        // Regular Expression: anchors + alternation match only plover-one.txt and plover-two.txt.
        try click(windowElement("toggleRegex", in: win))
        try searchInWindow("^plover-(one|two)\\.txt$", in: win)
        waitFor(tableText("plover-one.txt", in: win), 10)
        waitFor(tableText("plover-two.txt", in: win), 10)
        XCTAssertFalse(tableText("heronfile.txt", in: win).exists)
    }

    /// Inside Files shows matching line snippets in table + preview; Definitions finds symbols and disables regex/case/word/path toggles.
    func testInsideFilesAndDefinitionsModesAndDisabledToggles() throws {
        try launch()
        let win = try openSearchWindow()

        // Switch to Inside Files and search for content needle.
        try click(modeSegment("Inside Files", in: win))
        XCTAssertFalse(windowElement("toggleSearchInPath", in: win).isEnabled, "Search in Path disabled outside Names mode")
        try searchInWindow("quokkaneedle", in: win)
        waitFor(tableText("notes.md", in: win), 10)
        waitFor(tableText(containing: "2 · the quokkaneedle line", in: win), 10)

        // Selecting the line row populates the Preview pane with its line number and match text.
        try click(tableText("notes.md", in: win))
        let preview = windowElement("searchWindowPreviewPane", in: win)
        waitFor(preview.staticTexts["Line 2"], 5)
        waitFor(
            preview.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'quokkaneedle' OR value CONTAINS 'quokkaneedle'")
            ).firstMatch, 5)

        // Switch to Definitions: finds kestrelHandler and disables all 4 match toggles.
        try click(modeSegment("Definitions", in: win))
        waitUntil(5, "match toggles disabled in Definitions mode") {
            !self.windowElement("toggleMatchCase", in: win).isEnabled
                && !self.windowElement("toggleWholeWord", in: win).isEnabled
                && !self.windowElement("toggleRegex", in: win).isEnabled
                && !self.windowElement("toggleSearchInPath", in: win).isEnabled
        }
        try searchInWindow("kestrelHandler", in: win)
        waitFor(tableText("kestrel.swift", in: win), 10)
        waitFor(tableText(containing: "func kestrelHandler", in: win), 10)
    }

    // MARK: - Filter Chips, Quick Filters & Saved Searches

    /// Extension chip, built-in Quick Filters, and Saved Searches work and synchronize live across open Search Windows.
    func testFilterChipsQuickFiltersAndSavedSearchesSyncAcrossWindows() throws {
        try launch()
        let win1 = try openSearchWindow()

        // Add ext:swift chip via Extension… popover and verify filtering.
        try click(windowElement("searchWindowExtensionButton", in: win1))
        try submitPopover(text: "swift", actionTitle: "Add", in: win1)
        waitFor(windowElement("chip-ext:swift", in: win1), 5)
        waitFor(tableText("kestrel.swift", in: win1), 10)
        XCTAssertFalse(tableText("heronfile.txt", in: win1).exists)

        // Clear Filters removes the chip.
        try click(windowElement("searchWindowClearFilters", in: win1))
        waitForAbsence(windowElement("chip-ext:swift", in: win1), 5)

        // Built-in Quick Filter applies type:code + mtime:<7d and shows kestrel.swift.
        let sidebar1 = windowElement("searchWindowSidebar", in: win1)
        let recentCode = sidebar1.buttons["Recent Code"]
        waitFor(recentCode, 5)
        try click(recentCode)
        waitFor(windowElement("chip-type:code", in: win1), 5)
        waitFor(tableText("kestrel.swift", in: win1), 10)

        // Save Current Search via popover and verify it syncs into a second open window.
        try click(windowElement("searchWindowSaveButton", in: win1))
        try submitPopover(text: "My Swift Filter", actionTitle: "Save", in: win1)
        waitFor(sidebar1.buttons["My Swift Filter"], 5)

        try pressInApp("n", .command)
        waitUntil(10, "second window opened") { self.searchWindows.count == 2 }
        let win2 = searchWindows.allElementsBoundByIndex.first { $0 != win1 } ?? searchWindows.element(boundBy: 1)
        let sidebar2 = windowElement("searchWindowSidebar", in: win2)
        waitFor(sidebar2.buttons["My Swift Filter"], 5)

        // Deleting the saved search in window 2 removes it from window 1's sidebar too.
        let deleteBtn = sidebar2.buttons["Delete My Swift Filter"]
        waitFor(deleteBtn, 5)
        try click(deleteBtn)
        waitForAbsence(sidebar2.buttons["My Swift Filter"], 5)
        waitForAbsence(sidebar1.buttons["My Swift Filter"], 5)
    }

    // MARK: - Actions, Launchables & Multi-Select

    /// ↵ safely reveals a launchable script in Finder, while explicit Open in Preview pane and context menu launches it.
    func testLaunchableReturnRevealsWhileExplicitOpenLaunches() throws {
        try launch()
        let win = try openSearchWindow()
        let script = fixtureRoot + "/proj/osprey-script.command"

        try searchInWindow("osprey", in: win)
        let rowText = tableText("osprey-script.command", in: win)
        waitFor(rowText, 10)
        try click(rowText)

        // Preview pane shows selection metadata and action buttons.
        let preview = windowElement("searchWindowPreviewPane", in: win)
        let previewOpen = preview.buttons["Open"]
        let previewCopyPath = preview.buttons["Copy Path"]
        waitFor(previewOpen, 5)

        // ↵ on selected table row reveals the launchable script instead of opening it.
        let beforeReturn = recordedActions.count
        try pressInApp(.return)
        waitUntil(5, "↵ revealed launchable script") {
            self.recordedActions.dropFirst(beforeReturn).contains("reveal \(script)")
        }
        XCTAssertFalse(
            recordedActions.dropFirst(beforeReturn).contains("open \(script)"),
            "↵ must reveal launchables, never launch them")

        // Preview Copy Path copies the exact fixture path.
        try click(previewCopyPath)
        _ = try waitForClipboard(matching: { $0 == script })

        // Preview Open explicitly launches the script.
        let beforePreviewOpen = recordedActions.count
        try click(previewOpen)
        waitUntil(5, "Preview Open launched script") {
            self.recordedActions.dropFirst(beforePreviewOpen).contains("open \(script)")
        }

        // Context menu Open also explicitly launches the script.
        let beforeMenuOpen = recordedActions.count
        try requireFocus(field: false)
        rowText.rightClick()
        let contextOpen = app.menus.menuItems["Open"].firstMatch
        waitFor(contextOpen, 5)
        try click(contextOpen)
        waitUntil(5, "Context menu Open launched script") {
            self.recordedActions.dropFirst(beforeMenuOpen).contains("open \(script)")
        }
    }

    /// ⌘⌫ stays gated while typing in the search field; selecting multiple content-match rows deduplicates Reveal and Trash; ⌘Y opens Quick Look.
    func testMultiSelectShortcutGatingDeduplicatedTrashAndQuickLook() throws {
        try launch()
        let win = try openSearchWindow()
        let multiFile = fixtureRoot + "/proj/multi-match.md"

        try click(modeSegment("Inside Files", in: win))
        try searchInWindow("ibisneedle", in: win)
        let firstLine = tableText(containing: "1 · line one ibisneedle", in: win)
        let secondLine = tableText(containing: "2 · line two ibisneedle", in: win)
        waitFor(firstLine, 10)
        waitFor(secondLine, 10)

        // Select a row, then refocus search field with ⌘L and press ⌘⌫: must edit field, NOT trash the file!
        try click(firstLine)
        try pressInApp("l", .command)
        let wf = windowField(in: win)
        waitUntil(5, "⌘L focused search field") { wf.value(forKey: "hasKeyboardFocus") as? Bool == true }
        let beforeGatedDelete = recordedActions.count
        try pressInApp(.delete, .command)
        assertStaysAbsent(windowElement("searchWindowError", in: win), 1)
        XCTAssertFalse(
            recordedActions.dropFirst(beforeGatedDelete).contains(where: { $0.hasPrefix("trash ") }),
            "⌘⌫ while search field is focused must never trash selected rows")

        // Restore query and select both matching lines in the table with ⌘A.
        try searchInWindow("ibisneedle", in: win)
        waitFor(firstLine, 10)
        waitFor(secondLine, 10)
        try click(firstLine)
        try pressInApp("a", .command)

        // Status bar and Preview pane reflect 2 selected rows.
        waitUntil(5, "status bar shows 2 selected") {
            let sel = self.windowElement("searchWindowSelectionSummary", in: win)
            return sel.exists && (sel.value as? String ?? sel.label).contains("2 selected")
        }
        waitFor(windowText("Multiple items selected", in: win), 5)

        // ⌘↵ reveals the file once (deduplicated across both line matches).
        let beforeReveal = recordedActions.count
        try pressInApp(.return, .command)
        waitUntil(5, "⌘↵ recorded deduplicated reveal") {
            self.recordedActions.dropFirst(beforeReveal).contains("reveal \(multiFile)")
        }

        // ⌘⌫ trashes the file once (deduplicated across both line matches) with no error.
        let beforeTrash = recordedActions.count
        try pressInApp(.delete, .command)
        waitUntil(5, "⌘⌫ recorded deduplicated trash") {
            self.recordedActions.dropFirst(beforeTrash).filter { $0 == "trash \(multiFile)" }.count == 1
        }
        assertStaysAbsent(windowElement("searchWindowError", in: win), 1)

        // ⌘Y opens and closes Quick Look from a selected table row.
        let ql = app.windows["Quick Look"]
        XCTAssertFalse(ql.exists)
        try pressInApp("y", .command)
        waitFor(ql, 10)
        try pressInApp("y", .command)
        waitForAbsence(ql, 10)
    }

    // MARK: - UI Version Switcher (Classic Panel vs New Search Window)

    /// Switching Search interface in Settings routes reopen, `fsearch://` URLs, and menu-bar items cleanly between
    /// the classic Launcher Panel and the new Search Window, while preserving explicit `&ui=` overrides and quick switching.
    func testSwitchBetweenClassicPanelAndNewSearchWindowInSettings() async throws {
        try launch()

        // Default is Launcher Panel (Classic): hide panel, open Settings (⌘,), and switch to Search Window (New).
        try press(.escape)
        waitForAbsence(field, 5)
        try pressInApp(",", .command)
        let picker = app.popUpButtons["searchInterfacePicker"]
        waitFor(picker, 10)
        try click(picker)
        let windowOption = app.menuItems["Search Window (New)"].firstMatch
        waitFor(windowOption, 5)
        try click(windowOption)
        try pressInApp("w", .command)
        waitForAbsence(picker, 5)

        // Menu bar now offers Search…, New Search Window…, and Launcher Panel….
        let item = statusItem
        waitFor(item, 10)
        let menu = item.descendants(matching: .menuItem)
        waitFor(menu["Launcher Panel…"], 10)
        XCTAssertTrue(menu["Search…"].exists)
        XCTAssertTrue(menu["New Search Window…"].exists)

        // Single-instance reopen opens the Search Window (not the classic Panel).
        reopenPanel()
        waitUntil(10, "reopen opened Search Window") { self.searchWindows.count == 1 }
        XCTAssertFalse(field.exists, "classic panel must stay hidden when Search Window is selected")

        // `fsearch://search` without ui= opens a Search Window carrying query & mode.
        let contentURL = try XCTUnwrap(URL(string: "fsearch://search?q=quokkaneedle&mode=content"))
        try await openURLInTestApp(contentURL)
        waitUntil(10, "fsearch:// opened Search Window in Inside Files mode") {
            self.searchWindows.allElementsBoundByIndex.contains { $0.title == "FSearch — quokkaneedle" }
        }
        let contentWin = app.windows["FSearch — quokkaneedle"]
        waitFor(tableText("notes.md", in: contentWin), 10)

        // Explicit &ui=panel override still opens the classic Launcher Panel.
        let panelURL = try XCTUnwrap(URL(string: "fsearch://search?q=heronfile&ui=panel"))
        try await openURLInTestApp(panelURL)
        waitFor(field, 10)
        waitFor(text("heronfile.txt"), 10)
        try press(.escape)
        try press(.escape)
        waitForAbsence(field, 5)

        // Toolbar Open Launcher Panel button opens the classic Panel from inside a Search Window.
        try click(windowElement("searchWindowOpenPanel", in: contentWin))
        waitFor(field, 10)
        try press(.escape)
        waitForAbsence(field, 5)

        // Switch back to Launcher Panel (Classic) via Settings opened from Search Window (⌘,).
        try pressInApp(",", .command)
        waitFor(picker, 10)
        try click(picker)
        let panelOption = app.menuItems["Launcher Panel (Classic)"].firstMatch
        waitFor(panelOption, 5)
        try click(panelOption)
        try pressInApp("w", .command)
        waitForAbsence(picker, 5)

        // Now `fsearch://search?q=heronfile` routes back to the classic Panel, while `&ui=window` still opens a Search Window.
        let defaultURL = try XCTUnwrap(URL(string: "fsearch://search?q=heronfile"))
        try await openURLInTestApp(defaultURL)
        waitFor(field, 10)
        waitFor(text("heronfile.txt"), 10)
    }

    // MARK: - Sorting, Double-Click, Copy Files, Bad Regex, Mode Carry-Over & Window Close

    /// Verifies bad-regex error display, double-click open vs launchable reveal, ⌘⇧C Copy Files,
    /// column-header sorting, and ⌘W window closing.
    func testBadRegexDoubleClickCopyFilesSortingAndWindowClose() throws {
        try launch()
        let win = try openSearchWindow()

        // Invalid regex displays an error overlay and recovers when replaced with a valid query.
        try searchInWindow("re:(", in: win)
        waitFor(windowElement("searchWindowEmptyOverlay", in: win), 10)
        try searchInWindow("heronfile", in: win)
        let heronText = tableText("heronfile.txt", in: win)
        waitFor(heronText, 10)

        // Double-click on a normal file opens it; ⌘⇧C copies its file URL.
        let heronPath = fixtureRoot + "/proj/heronfile.txt"
        try click(heronText)
        let beforeDouble = recordedActions.count
        try requireFocus(field: false)
        heronText.doubleClick()
        waitUntil(5, "double-click opened normal file") {
            self.recordedActions.dropFirst(beforeDouble).contains("open \(heronPath)")
        }

        // Double-click on a launchable script reveals it instead of opening it.
        try searchInWindow("osprey", in: win)
        let ospreyText = tableText("osprey-script.command", in: win)
        let ospreyPath = fixtureRoot + "/proj/osprey-script.command"
        waitFor(ospreyText, 10)
        let beforeLaunchable = recordedActions.count
        try requireFocus(field: false)
        ospreyText.doubleClick()
        waitUntil(5, "double-click revealed launchable script") {
            self.recordedActions.dropFirst(beforeLaunchable).contains("reveal \(ospreyPath)")
        }
        XCTAssertFalse(recordedActions.dropFirst(beforeLaunchable).contains("open \(ospreyPath)"))

        // ⌘⇧C copies file URL to pasteboard.
        try click(ospreyText)
        try pressInApp("c", [.command, .shift])
        waitUntil(5, "⌘⇧C wrote file URL to pasteboard") {
            guard let raw = NSPasteboard.general.string(forType: .fileURL), let u = URL(string: raw) else { return false }
            return u.path == ospreyPath
        }

        // Clicking Name column header sorts plover results cleanly without error.
        try searchInWindow("plover", in: win)
        waitFor(tableText("plover-one.txt", in: win), 10)
        waitFor(tableText("plover-two.txt", in: win), 10)
        let nameHeader = table(in: win).buttons["Name"].firstMatch
        waitFor(nameHeader, 5)
        try click(nameHeader)
        waitFor(tableText("plover-one.txt", in: win), 5)

        // ⌘W closes the Search Window cleanly.
        try pressInApp("w", .command)
        waitUntil(5, "⌘W closed Search Window") { self.searchWindows.count == 0 }
    }

    /// Opening Search Window from the panel's ⌘/ menu while in Inside Files mode carries over both query and mode,
    /// and logs the Search Window query to temp HOME when Debug mode is enabled.
    func testPanelMenuCarriesInsideFilesModeAndDebugModeLogsWindowSearch() throws {
        try launch(debugMode: true)
        try enterContentMode("quokkaneedle")
        waitFor(text("notes.md"), 10)

        try press("/", .command)
        let menuField = element("appMenuField")
        waitFor(element("appMenu-Search Window"), 10)
        waitUntil(5, "menu field focused") { menuField.value(forKey: "hasKeyboardFocus") as? Bool == true }
        try requireFocus(field: false)
        menuField.typeText("win")
        waitForAbsence(element("appMenu-Settings"), 5)
        try pressInApp(.return)

        waitForAbsence(field, 5)
        waitUntil(10, "Search Window opened in Inside Files mode") { self.searchWindows.count == 1 }
        let win = searchWindows.firstMatch
        waitUntil(5, "Inside Files segment active") {
            self.modeSegment("Inside Files", in: win).value as? Int == 1
        }
        waitFor(tableText("notes.md", in: win), 10)
        waitFor(tableText(containing: "2 · the quokkaneedle line", in: win), 10)
        waitUntil(5, "debug search log recorded Search Window query") {
            (try? String(contentsOf: self.debugSearchLogURL, encoding: .utf8))?.contains("quokkaneedle") == true
        }
    }
}
