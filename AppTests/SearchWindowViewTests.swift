import AppKit
import FSearchKit
import Foundation
import Quartz
import SwiftUI
import Testing

@testable import FSearch

extension AppTests {
    @Suite @MainActor
    struct SearchWindowTests {
        @Test func actionsHandleMultiSelectLaunchablesMissingFilesAndTrash() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let docPath = env.file("notes.txt", "hello")
            let appPath = env.file("Tool.app", "x")
            let missingPath = env.dir.appendingPathComponent("gone.txt").path
            env.workspace.missing.insert(missingPath)

            let docRow = SearchWindowRow(item: .file(Wire.hit(docPath)))
            let appRow = SearchWindowRow(item: .file(Hit(path: appPath, kind: "dir", size: 0, mtime: 0, score: 1)))
            let missingRow = SearchWindowRow(item: .file(Wire.hit(missingPath)))
            var errors: [String] = []
            let onError: @MainActor (String) -> Void = { errors.append($0) }

            // Empty selections are no-ops.
            SearchWindowActions.openSelected([], app: env.app, onError: onError)
            let revEmpty = SearchWindowActions.revealSelected([], onError: onError)
            #expect(!revEmpty)
            SearchWindowActions.copyPaths([])
            let copyEmpty = SearchWindowActions.copyFiles([], onError: onError)
            #expect(!copyEmpty)
            SearchWindowActions.openTerminal([], onError: onError)
            let qlEmpty = SearchWindowActions.toggleQuickLook([], onError: onError)
            #expect(!qlEmpty)
            var refreshes = 0
            await SearchWindowActions.trashSelected([], app: env.app, onError: onError) { refreshes += 1 }
            #expect(refreshes == 0 && errors.isEmpty)

            // Open selected: doc opens & becomes recent; .app reveals instead of launching by default.
            SearchWindowActions.openSelected([docRow, appRow], app: env.app, onError: onError)
            #expect(env.workspace.opened == [URL(fileURLWithPath: docPath)])
            #expect(env.workspace.revealed == [[URL(fileURLWithPath: appPath)]])
            #expect(env.app.recents.paths.contains(docPath))

            // Explicit Open launches .app directly and records it in Recents.
            SearchWindowActions.openSelected([appRow], app: env.app, respectLaunchableReveal: false, onError: onError)
            #expect(env.workspace.opened == [URL(fileURLWithPath: docPath), URL(fileURLWithPath: appPath)])
            #expect(env.app.recents.paths.contains(appPath))

            // Multiple content-match rows for the same file deduplicate before path-level operations.
            let line1 = SearchWindowRow(item: .line(path: docPath, match: Match(line: 1, text: "hello")))
            let line2 = SearchWindowRow(item: .line(path: docPath, match: Match(line: 2, text: "hello again")))
            SearchWindowActions.copyPaths([line1, line2, appRow])
            #expect(env.pasteboard.string(forType: .string) == "\(docPath)\n\(appPath)")
            let revDedup = SearchWindowActions.revealSelected([line1, line2], onError: onError)
            #expect(revDedup)
            #expect(env.workspace.revealed.last == [URL(fileURLWithPath: docPath)])
            let copyDedup = SearchWindowActions.copyFiles([line1, line2], onError: onError)
            #expect(copyDedup)
            #expect((env.pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]) == [URL(fileURLWithPath: docPath)])

            // Reveal selected batches existing URLs and reports missing once.
            let revMixed = SearchWindowActions.revealSelected([docRow, missingRow], onError: onError)
            #expect(revMixed)
            #expect(env.workspace.revealed.last == [URL(fileURLWithPath: docPath)])
            #expect(errors.count == 1)
            let revMissing = SearchWindowActions.revealSelected([missingRow], onError: onError)
            #expect(!revMissing)

            // Copy paths joins with newlines.
            SearchWindowActions.copyPaths([docRow, appRow])
            #expect(env.pasteboard.string(forType: .string) == "\(docPath)\n\(appPath)")

            // Copy files puts existing URLs on pasteboard and reports missing.
            errors = []
            let copyMixed = SearchWindowActions.copyFiles([docRow, missingRow], onError: onError)
            #expect(copyMixed)
            #expect(errors.count == 1)
            let copyMissing = SearchWindowActions.copyFiles([missingRow], onError: onError)
            #expect(!copyMissing)

            // Open Terminal and Quick Look act on first row.
            env.workspace.apps["com.apple.Terminal"] = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            SearchWindowActions.openTerminal([docRow], onError: onError)
            #expect(env.workspace.openedWith.count == 1)
            let qlOK = SearchWindowActions.toggleQuickLook([docRow], onError: onError)
            #expect(qlOK)
            QuickLookSource.shared.close()

            // Trash deduplicates multiple rows pointing at the same file and triggers refresh once without error.
            errors = []
            await SearchWindowActions.trashSelected([line1, line2], app: env.app, onError: onError) { refreshes += 1 }
            #expect(env.workspace.trashed == [URL(fileURLWithPath: docPath)])
            #expect(errors.isEmpty)
            #expect(refreshes == 1)

            struct Boom: Error {}
            env.workspace.trashError = Boom()
            let beforeErrors = errors.count
            await SearchWindowActions.trashSelected([appRow], app: env.app, onError: onError) { refreshes += 1 }
            #expect(errors.count == beforeErrors + 1)
            #expect(refreshes == 1)
        }

        @Test func comparatorOrdersRowsAndMapsSortDirections() {
            let a = SearchWindowRow(item: .file(Hit(path: "/p/a.txt", kind: "file", size: 10, mtime: 100, score: 1)))
            let b = SearchWindowRow(item: .file(Hit(path: "/p/b.txt", kind: "file", size: 20, mtime: 200, score: 2)))
            let fwd = SearchWindowComparator(.name, order: .forward)
            let rev = SearchWindowComparator(.name, order: .reverse)
            #expect(fwd.compare(a, b) == .orderedAscending)
            #expect(fwd.compare(b, a) == .orderedDescending)
            #expect(fwd.compare(a, a) == .orderedSame)
            #expect(rev.compare(a, b) == .orderedDescending)
            #expect(SearchWindowComparator.from(SearchWindowSort(column: .size, direction: .ascending)).first?.order == .forward)
            #expect(SearchWindowComparator.from(SearchWindowSort(column: .size, direction: .descending)).first?.order == .reverse)
        }

        @Test func managerOpensMultipleIndependentWindowsAndCleansUpOnClose() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let mgr = SearchWindowManager()
            defer { mgr.closeAll() }

            #expect(SearchWindowManager.windowTitle(for: "  ") == "FSearch")
            #expect(SearchWindowManager.windowTitle(for: "hello") == "FSearch — hello")

            // Default open seam works inertly in unit tests.
            SearchWindowManager.open(env.app, "seam")
            #expect(SearchWindowManager.shared.openCount == 1)
            SearchWindowManager.shared.closeAll()
            #expect(SearchWindowManager.shared.openCount == 0)

            let id1 = mgr.openWindow(app: env.app, initialQuery: "alpha", inert: true)
            let id2 = mgr.openWindow(app: env.app, initialQuery: "beta", initialMode: .content, inert: true)
            #expect(mgr.openCount == 2)
            #expect(mgr.windows[id1]?.title == "FSearch — alpha")
            #expect(mgr.windows[id2]?.title == "FSearch — beta")
            #expect(mgr.windows[id1]?.canBecomeKey == false)
            #expect(mgr.windows[id2]?.canBecomeMain == false)
            let browserWin = try #require(mgr.windows[id1])
            #expect(browserWin.acceptsPreviewPanelControl(nil))
            if let qlPanel = QLPreviewPanel.shared() {
                browserWin.beginPreviewPanelControl(qlPanel)
                #expect(qlPanel.dataSource === QuickLookSource.shared)
                browserWin.endPreviewPanelControl(qlPanel)
                #expect(qlPanel.dataSource == nil)
            }

            // Clicking New Search Window inside an open window opens a third independent window.
            let win1 = try #require(mgr.windows[id1])
            let newBtn = try #require(await axWait(id: "searchWindowNew", in: win1))
            newBtn.press()
            #expect(await eventually { mgr.openCount == 3 })

            mgr.closeWindow(id: id1)
            #expect(mgr.openCount == 2)
            mgr.closeAll()
            #expect(mgr.openCount == 0)
        }

        @Test func panelMenuAndAppCommandOpenSearchWindowThroughSeam() {
            let env = TestEnv()
            defer { env.tearDown() }
            var openedQueries: [String] = []
            let savedOpen = SearchWindowManager.open
            SearchWindowManager.open = { _, q in openedQueries.append(q) }
            defer { SearchWindowManager.open = savedOpen }

            env.app.search.query = "invoice"
            AppMenuActions.run(.searchWindow, app: env.app)
            #expect(openedQueries == ["invoice"])
            #expect(env.panel.hides == 1)

            let pc = PanelController()
            pc.show(app: env.app)
            defer { pc.hide(returnFocus: false) }
            pc.run(.searchWindow)
            #expect(openedQueries == ["invoice", ""])
        }

        @Test func appStateWindowModelLogsInDebugModeAndRecoversAfterDisconnect() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.daemon.onSearch = { _ in SearchReply(tookUs: 250, hits: [Wire.hit("/p/doc.md")]) }
            env.app.debugMode = true
            let model = env.app.makeSearchWindowModel()
            model.query = "doc"
            await model.refresh()
            env.app.log.flush()
            #expect(env.app.log.entries().last?.query == "doc")
            #expect(model.rows.count == 1)

            // Disconnected search triggers daemon recovery and refreshes the originating window model once (coalesced).
            final class Counter: @unchecked Sendable { var n = 0 }
            let attempts = Counter()
            env.daemon.onSearch = { _ in
                attempts.n += 1
                if attempts.n <= 2 { throw DaemonError.disconnected }
                return SearchReply(tookUs: 120, hits: [Wire.hit("/p/recovered.md")])
            }
            model.query = "recovered"
            await model.refresh()
            // Simulate a second disconnect from the same window while recovery is in flight: coalesces by identity.
            env.app.searchSettled(
                .failed(.disconnected), recoveryKey: ObjectIdentifier(model), refreshOnRecovery: { await model.refresh() })
            #expect(await eventually { model.phase == .results && model.rows.map(\.rawName) == ["recovered.md"] })
            #expect(attempts.n <= 3)
        }

        @Test func rowShortcutsDisableWhileEditingTextOrPopovers() {
            #expect(SearchWindowView.rowShortcutsEnabled(searchFocused: false, popoverOpen: false, hasSelection: true, tableFocused: true))
            #expect(!SearchWindowView.rowShortcutsEnabled(searchFocused: true, popoverOpen: false, hasSelection: true, tableFocused: true))
            #expect(!SearchWindowView.rowShortcutsEnabled(searchFocused: false, popoverOpen: true, hasSelection: true, tableFocused: true))
            #expect(
                !SearchWindowView.rowShortcutsEnabled(searchFocused: false, popoverOpen: false, hasSelection: false, tableFocused: true))
            #expect(
                !SearchWindowView.rowShortcutsEnabled(searchFocused: false, popoverOpen: false, hasSelection: true, tableFocused: false))

            // First-responder classification: NSTableView & child views allow row shortcuts; NSTextView / NSButton / nil do not.
            let table = NSTableView()
            let child = NSView()
            table.addSubview(child)
            #expect(SearchWindowView.firstResponderAllowsRowShortcuts(table))
            #expect(SearchWindowView.firstResponderAllowsRowShortcuts(child))
            #expect(!SearchWindowView.firstResponderAllowsRowShortcuts(NSTextView()))
            #expect(!SearchWindowView.firstResponderAllowsRowShortcuts(NSButton()))
            #expect(!SearchWindowView.firstResponderAllowsRowShortcuts(NSSegmentedControl()))
            #expect(!SearchWindowView.firstResponderAllowsRowShortcuts(NSView()))
            #expect(!SearchWindowView.firstResponderAllowsRowShortcuts(nil))
        }

        @Test func savedSearchesSynchronizeAcrossOpenWindows() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let saved = SavedSearch(name: "Shared Filter", query: "shared")
            _ = env.app.savedSearches.add(saved)

            let view1 = SearchWindowView(model: env.app.makeSearchWindowModel(), savedStore: env.app.savedSearches)
                .environmentObject(env.app)
            let view2 = SearchWindowView(model: env.app.makeSearchWindowModel(), savedStore: env.app.savedSearches)
                .environmentObject(env.app)
            let w1 = await render(view1, size: NSSize(width: 900, height: 500))
            let w2 = await render(view2, size: NSSize(width: 900, height: 500))
            defer {
                w1.close()
                w2.close()
            }

            #expect(await axWait("Shared Filter", in: w1) != nil)
            #expect(await axWait("Shared Filter", in: w2) != nil)

            // Deleting in window 1 removes it from window 2's sidebar too.
            try #require(await axWait("Delete Shared Filter", in: w1)).press()
            #expect(await eventually { axNode("Shared Filter", in: w2) == nil })
        }

        @Test func previewPaneRendersEmptySingleLineAndMultiSelectionStates() async throws {
            var opens = 0, reveals = 0, copies = 0
            let empty = await render(
                SearchPreviewPane(selected: [], onOpen: { opens += 1 }, onReveal: { reveals += 1 }, onCopyPath: { copies += 1 }),
                size: NSSize(width: 300, height: 420))
            defer { empty.close() }
            #expect(await axWait("Select a file to preview", in: empty) != nil)

            let lineRow = SearchWindowRow(item: .line(path: "/tmp/demo.swift", match: Match(line: 12, text: "struct Demo {}")))
            let single = await render(
                SearchPreviewPane(selected: [lineRow], onOpen: { opens += 1 }, onReveal: { reveals += 1 }, onCopyPath: { copies += 1 }),
                size: NSSize(width: 300, height: 420))
            defer { single.close() }
            let openBtn = try #require(await axWait("Open", in: single))
            openBtn.press()
            try #require(axNode("Reveal", in: single)).press()
            try #require(axNode("Copy Path", in: single)).press()
            #expect(opens == 1 && reveals == 1 && copies == 1)

            let r1 = SearchWindowRow(item: .file(Hit(path: "/tmp/a.txt", kind: "file", size: 100, mtime: 1000, score: 1)))
            let r2 = SearchWindowRow(item: .file(Hit(path: "/tmp/b.txt", kind: "file", size: 200, mtime: 2000, score: 1)))
            let multi = await render(
                SearchPreviewPane(selected: [r1, r2], onOpen: { opens += 1 }, onReveal: { reveals += 1 }, onCopyPath: { copies += 1 }),
                size: NSSize(width: 300, height: 420))
            defer { multi.close() }
            #expect(await axWait("Multiple items selected", in: multi) != nil)
        }

        @Test func helperSubviewsPopoversAndContextMenuRenderAndAct() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let path = env.file("hello.swift", "let hello = 1")
            let lineRow = SearchWindowRow(item: .line(path: path, match: Match(line: 1, text: "let hello = 1")))
            let fileRow = SearchWindowRow(item: .file(Hit(path: path, kind: "file", size: 13, mtime: 1000, score: 10)))

            // SearchWindowNameCell renders both file and content-match rows.
            let cells = await render(
                VStack(alignment: .leading) {
                    SearchWindowNameCell(row: fileRow)
                    SearchWindowNameCell(row: lineRow)
                }, size: NSSize(width: 260, height: 80))
            defer { cells.close() }
            #expect(await axWait("1 · let hello = 1", in: cells) != nil)

            // SearchWindowInputPopover renders and invokes onSubmit.
            var submitted = 0
            let popover = await render(
                SearchWindowInputPopover(
                    heading: "Save Search", placeholder: "Name", actionTitle: "Save",
                    text: .constant("Notes"), onSubmit: { submitted += 1 }),
                size: NSSize(width: 240, height: 110))
            defer { popover.close() }
            try #require(await axWait("Save", in: popover)).press()
            #expect(submitted == 1)

            // SearchWindowContextMenu buttons route through SearchWindowActions; explicit Open launches .app items.
            let appPath = env.file("LaunchMe.app", "x")
            let appRow = SearchWindowRow(item: .file(Hit(path: appPath, kind: "dir", size: 0, mtime: 0, score: 5)))
            let launchMenuView = await render(
                VStack { SearchWindowContextMenu(rows: [appRow], app: env.app, onError: { _ in }, refresh: {}) },
                size: NSSize(width: 220, height: 220))
            defer { launchMenuView.close() }
            try #require(await axWait("Open", in: launchMenuView)).press()
            #expect(env.workspace.opened == [URL(fileURLWithPath: appPath)])
            #expect(env.workspace.revealed.isEmpty)

            env.workspace.apps["com.apple.Terminal"] = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            var refreshes = 0
            let menuView = await render(
                VStack {
                    SearchWindowContextMenu(
                        rows: [fileRow], app: env.app, onError: { _ in },
                        refresh: { refreshes += 1 })
                }, size: NSSize(width: 220, height: 280))
            defer { menuView.close() }
            try #require(await axWait("Open", in: menuView)).press()
            try #require(axNode("Reveal in Finder", in: menuView)).press()
            try #require(axNode("Quick Look", in: menuView)).press()
            QuickLookSource.shared.close()
            try #require(axNode("Copy Path", in: menuView)).press()
            try #require(axNode("Copy File", in: menuView)).press()
            try #require(axNode("Open Folder in Terminal", in: menuView)).press()
            try #require(axNode("Move to Trash", in: menuView)).press()
            #expect(await eventually { refreshes == 1 })
            #expect(env.workspace.opened == [URL(fileURLWithPath: appPath), URL(fileURLWithPath: path)])
            #expect(env.workspace.trashed == [URL(fileURLWithPath: path)])

            // pickFolder respects override and returns nil under inert mode.
            #expect(SearchWindowView.pickFolder(override: { "/tmp/x" }, inert: true) == "/tmp/x")
            #expect(SearchWindowView.pickFolder(override: nil, inert: true) == nil)
        }

        @Test func searchWindowViewRendersAndDrivesTogglesFiltersAndSavedSearches() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let fileA = env.file("alpha.swift", "let x = 1")
            let fileB = env.file("beta.md", "# notes")
            env.daemon.onSearch = { _ in
                SearchReply(
                    tookUs: 420,
                    hits: [
                        Hit(path: fileA, kind: "file", size: 1200, mtime: 1_700_000_000, score: 90),
                        Hit(path: fileB, kind: "file", size: 500, mtime: 1_700_000_100, score: 80),
                    ])
            }
            let model = env.app.makeSearchWindowModel()
            model.query = "alpha"
            await model.refresh()
            _ = env.app.savedSearches.add(
                SavedSearch(name: "My Swift", query: "alpha", chips: [SearchFilterChip(kind: .ext, value: "swift")]))

            var newWindowCount = 0
            var titles: [String] = []
            let view = SearchWindowView(
                model: model,
                savedStore: env.app.savedSearches,
                onNewWindow: { newWindowCount += 1 },
                onTitleChange: { titles.append($0) },
                selection: [fileA],
                windowError: "Sample error",
                pickFolderOverride: { env.dir.path }
            ).environmentObject(env.app)

            let w = await render(view, size: NSSize(width: 1040, height: 640))
            defer { w.close() }
            #expect(await axWait(id: "searchWindowField", in: w) != nil)
            #expect(await axWait(id: "searchWindowError", in: w) != nil)
            #expect(await axWait(id: "searchWindowSelectionSummary", in: w) != nil)
            #expect(await axWait(id: "searchWindowTiming", in: w) != nil)

            // Toggle match case, whole word, regex, search in path.
            try #require(axNode(id: "toggleMatchCase", in: w)).press()
            try #require(axNode(id: "toggleWholeWord", in: w)).press()
            try #require(axNode(id: "toggleRegex", in: w)).press()
            try #require(axNode(id: "toggleSearchInPath", in: w)).press()
            #expect(
                await eventually { model.options == SearchMatchOptions(matchCase: true, wholeWord: true, regex: true, searchInPath: true) })

            // Clear Filters resets match options and chips.
            try #require(await axWait(id: "searchWindowClearFilters", in: w)).press()
            #expect(await eventually { !model.options.hasAnyOption })

            // Apply saved search from sidebar (loads 2 rows + ext:swift chip).
            model.query = ""
            try #require(await axWait("My Swift", in: w)).press()
            #expect(await eventually { model.query == "alpha" && model.rows.count == 2 })
            #expect(titles.contains("alpha"))
            #expect(await axWait(id: "chip-ext:swift", in: w) != nil)

            // Remove active chip via its X button, and clear search field.
            try #require(await axWait("Remove ext:swift", in: w)).press()
            #expect(await eventually { model.chips.isEmpty })
            try #require(await axWait("Clear search", in: w)).press()
            #expect(await eventually { model.query.isEmpty })

            // Apply built-in Quick Filter preset.
            try #require(await axWait("Recent Code", in: w)).press()
            #expect(await eventually { model.chips.contains { $0.id == "type:code" } })

            // Delete saved search from sidebar.
            try #require(await axWait("Delete My Swift", in: w)).press()
            #expect(await eventually { env.app.savedSearches.load().isEmpty })

            // Toggle sidebar, preview pane, and trigger New Search Window button.
            try #require(axNode(id: "searchWindowToggleSidebar", in: w)).press()
            try #require(axNode(id: "searchWindowTogglePreview", in: w)).press()
            try #require(axNode(id: "searchWindowNew", in: w)).press()
            #expect(newWindowCount == 1)

            // Also render empty results, indexing, and error states cleanly.
            model.clearFilters()
            env.daemon.onSearch = { _ in SearchReply(tookUs: 50, hits: []) }
            model.query = "nomatch"
            await model.refresh()
            #expect(await axWait("No matching files", in: w) != nil)

            env.daemon.onSearch = { _ in throw DaemonError.indexing("building") }
            model.query = "idx"
            await model.refresh()
            #expect(await axWait("Indexing your disk… results will appear shortly", in: w) != nil)

            env.daemon.onSearch = { _ in throw DaemonError.disconnected }
            model.query = "disc"
            await model.refresh()
            #expect(await eventually { model.phase == .failed(.disconnected) })

            // In Definitions mode, regex/case/word match toggles are disabled because sym: ignores them.
            model.mode = .symbols
            #expect(await eventually { axNode(id: "toggleMatchCase", in: w)?.isEnabled == false })
            #expect(axNode(id: "toggleWholeWord", in: w)?.isEnabled == false)
            #expect(axNode(id: "toggleRegex", in: w)?.isEnabled == false)
            #expect(axNode(id: "toggleSearchInPath", in: w)?.isEnabled == false)
        }

        @Test func indexingWindowRetriesAutomaticallyUntilResultsArrive() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            final class Counter: @unchecked Sendable { var searches = 0 }
            let counter = Counter()
            env.daemon.onSearch = { _ in
                counter.searches += 1
                if counter.searches == 1 { throw DaemonError.indexing("building") }
                return SearchReply(tookUs: 110, hits: [Wire.hit("/p/indexed.md")])
            }
            let model = env.app.makeSearchWindowModel()
            model.query = "indexed"
            await model.refresh()
            #expect(model.phase == .indexing)

            let view = SearchWindowView(
                model: model, savedStore: env.app.savedSearches,
                indexingPollInterval: .milliseconds(10)
            ).environmentObject(env.app)
            let w = await render(view, size: NSSize(width: 900, height: 500))
            defer { w.close() }
            NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: w)

            #expect(await eventually { model.phase == .results && model.rows.map(\.rawName) == ["indexed.md"] })
            #expect(counter.searches >= 2)
        }

        @Test func searchInterfaceRoutesShortcutReopenURLsMenuAndPreviewShortcut() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let mgr = SearchWindowManager()
            defer { mgr.closeAll() }

            // Default is classic panel.
            #expect(env.app.searchInterface == .panel)
            env.app.togglePrimarySearch(panel: env.panel, windows: mgr)
            #expect(env.panel.shows == 1 && mgr.openCount == 0)
            env.app.togglePrimarySearch(panel: env.panel, windows: mgr)
            #expect(env.panel.hides == 1)
            env.app.reopenPrimarySearch(panel: env.panel, windows: mgr)
            #expect(env.panel.externalShows == 1)

            // URL override &ui=window opens a Search Window even when panel is default, hiding the panel.
            env.app.openSearchURL(SearchURL(query: "budget", mode: .content, interface: .window), panel: env.panel, windows: mgr)
            #expect(mgr.openCount == 1)
            #expect(env.panel.isVisible == false)
            mgr.closeAll()

            // Switch to new Search Window interface.
            env.app.searchInterface = .window
            #expect(env.app.searchInterface == .window)

            // Toggle opens a Search Window when none exist; activating while active with key Search Window hides app.
            env.app.togglePrimarySearch(panel: env.panel, windows: mgr)
            #expect(mgr.openCount == 1)
            let firstWin = try #require(mgr.windows.values.first)
            var hidApp = 0
            mgr.toggle(app: env.app, inert: false, appIsActive: true, keyWindow: firstWin, hideApp: { hidApp += 1 })
            #expect(hidApp == 1 && mgr.openCount == 1)

            // Reopen brings back existing Search Window rather than creating a duplicate or opening the panel.
            let showsBefore = env.panel.shows
            env.app.reopenPrimarySearch(panel: env.panel, windows: mgr)
            #expect(mgr.openCount == 1 && env.panel.shows == showsBefore)

            // URL without ui= follows Search Window preference; explicit &ui=panel still routes to panel.
            env.app.openSearchURL(SearchURL(query: "notes", mode: .symbols), panel: env.panel, windows: mgr)
            #expect(mgr.openCount == 2)
            env.app.openSearchURL(SearchURL(query: "quick", mode: .names, interface: .panel), panel: env.panel, windows: mgr)
            #expect(env.panel.openedSearches.last == SearchURL(query: "quick", mode: .names, interface: .panel))

            // Mode carry-over from panel FSearch menu into SearchWindowManager.openWithMode.
            var carried: [(String, SearchMode)] = []
            let savedOpenWithMode = SearchWindowManager.openWithMode
            SearchWindowManager.openWithMode = { _, q, m in carried.append((q, m)) }
            defer { SearchWindowManager.openWithMode = savedOpenWithMode }
            env.app.search.query = "needle"
            env.app.search.mode = .content
            AppMenuActions.run(.searchWindow, app: env.app)
            #expect(carried.count == 1 && carried.first?.0 == "needle" && carried.first?.1 == .content)

            // SearchBrowserWindow layout-independent ⌥⌘P detection and performKeyEquivalent.
            #expect(SearchBrowserWindow.isTogglePreviewEvent(characters: "π", modifiers: [.command, .option], keyCode: 35))
            #expect(SearchBrowserWindow.isTogglePreviewEvent(characters: "p", modifiers: [.command, .option], keyCode: 0))
            // Dvorak ⌥⌘L has keyCode 35 with character "l" and must NOT toggle preview.
            #expect(!SearchBrowserWindow.isTogglePreviewEvent(characters: "l", modifiers: [.command, .option], keyCode: 35))
            #expect(!SearchBrowserWindow.isTogglePreviewEvent(characters: "p", modifiers: [.command], keyCode: 35))
            #expect(!SearchBrowserWindow.isTogglePreviewEvent(characters: "p", modifiers: [.command, .option, .shift], keyCode: 35))
            let browser = SearchWindowManager.makeWindow(inert: true)
            let bridge = SearchWindowKeyBridge()
            var previewToggles = 0
            bridge.togglePreview = { previewToggles += 1 }
            browser.keyBridge = bridge
            let optCmdP = try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0,
                    windowNumber: 0, context: nil, characters: "π", charactersIgnoringModifiers: "p",
                    isARepeat: false, keyCode: 35))
            #expect(browser.performKeyEquivalent(with: optCmdP))
            #expect(previewToggles == 1)
            let repeatOptCmdP = try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [.command, .option], timestamp: 0,
                    windowNumber: 0, context: nil, characters: "π", charactersIgnoringModifiers: "p",
                    isARepeat: true, keyCode: 35))
            #expect(!browser.performKeyEquivalent(with: repeatOptCmdP))
            #expect(previewToggles == 1)
            let plainKey = try #require(
                NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a",
                    isARepeat: false, keyCode: 0))
            #expect(!browser.performKeyEquivalent(with: plainKey))

            // QuickLookSource owned by a SearchBrowserWindow passes ↑/↓ through while keeping ⌘Y close active.
            if let qlPanel = QLPreviewPanel.shared() {
                var panelMoves = 0
                let savedMove = QuickLookSource.shared.move
                QuickLookSource.shared.move = { _ in panelMoves += 1 }
                defer { QuickLookSource.shared.move = savedMove }
                QuickLookSource.shared.attach(qlPanel, owner: browser)
                #expect(
                    !QuickLookSource.shared.handleKeyDown(
                        characters: "", modifiers: [], keyCode: 125, isRepeat: false, inPreviewPanel: true))
                #expect(panelMoves == 0)
                #expect(
                    QuickLookSource.shared.handleKeyDown(
                        characters: "y", modifiers: .command, keyCode: 16, isRepeat: false, inPreviewPanel: true))
                // Detaching a different window must not strip browser's preview control.
                let other = SearchWindowManager.makeWindow(inert: true)
                QuickLookSource.shared.detach(qlPanel, owner: other)
                #expect(QuickLookSource.shared.isOwned(by: browser))
                QuickLookSource.shared.detach(qlPanel, owner: browser)
                #expect(!QuickLookSource.shared.isOwned(by: browser))
            }

            // Menu-bar openPrimarySearch activates/opens Search Window instead of hiding it.
            env.app.openPrimarySearch(panel: env.panel, windows: mgr)
            #expect(mgr.openCount == 2)
            // Global-shortcut toggle with another visible titled window preserves that window instead of calling hideApp.
            let otherTitled = NSWindow(
                contentRect: NSRect(x: -20_000, y: -20_000, width: 300, height: 200),
                styleMask: [.titled], backing: .buffered, defer: false)
            otherTitled.alphaValue = 0
            otherTitled.ignoresMouseEvents = true
            otherTitled.orderFrontRegardless()
            defer { otherTitled.close() }
            var hidAppWithOther = 0
            if let activeSearch = mgr.windows.values.first {
                mgr.toggle(
                    app: env.app, inert: false, appIsActive: true, keyWindow: activeSearch,
                    allWindows: [activeSearch, otherTitled], hideApp: { hidAppWithOther += 1 })
                #expect(hidAppWithOther == 0)
            }

            // Closing a Search Window clears keyBridge callbacks and contentView (no retain cycle / socket leak).
            let closedID = try #require(mgr.windows.keys.first)
            let closedWin = try #require(mgr.windows[closedID] as? SearchBrowserWindow)
            let closedBridge = closedWin.keyBridge
            mgr.closeWindow(id: closedID)
            #expect(closedWin.contentView == nil)
            #expect(closedWin.keyBridge == nil)
            #expect(closedBridge?.togglePreview == nil)
            #expect(closedBridge?.focusSearch == nil)

            // Column customization persistence + Uninstaller key registration.
            let custom = TableColumnCustomization<SearchWindowRow>()
            SearchWindowView.saveColumnCustomization(custom, to: env.defaults)
            #expect(env.defaults.data(forKey: SearchWindowView.columnCustomizationKey) != nil)
            _ = SearchWindowView.loadColumnCustomization(from: env.defaults)
            #expect(Uninstaller.defaultsKeys.contains(SearchInterface.storageKey))
            #expect(Uninstaller.defaultsKeys.contains(SearchWindowView.columnCustomizationKey))

            // rowsForAction(ids: []) must return empty so empty-space table clicks never act on selection.
            let m = env.app.makeSearchWindowModel()
            env.daemon.onSearch = { _ in SearchReply(tookUs: 40, hits: [Wire.hit("/p/a.txt")]) }
            m.query = "a"
            await m.refresh()
            let view = SearchWindowView(model: m, savedStore: env.app.savedSearches, selection: ["/p/a.txt"])
            #expect(view.rowsForAction(ids: []).isEmpty)
            #expect(view.rowsForAction(ids: ["/p/a.txt"]).count == 1)

            // OnboardingFlow clears stale indexReady when daemon transitions to .indexing or .failed.
            let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: .indexing)
            env.daemon.onStatus = { _ in Wire.status(entries: 42, fullDiskAccess: false) }
            await env.app.daemon.refresh()
            flow.apply()
            #expect(flow.facts.indexReady == true && flow.entries == 42)
            env.daemon.onStatus = { _ in throw DaemonError.indexing("rebuilding") }
            await env.app.daemon.refresh()
            flow.apply()
            #expect(flow.facts.indexReady == false && flow.entries == 0)

            // MenuContent shows Launcher Panel… item when Search Window is the default UI.
            let menuView = MenuContent(app: env.app)
            let mw = await render(menuView, size: NSSize(width: 240, height: 320))
            defer { mw.close() }
            #expect(await axWait("Launcher Panel…", in: mw) != nil)
        }
    }
}
