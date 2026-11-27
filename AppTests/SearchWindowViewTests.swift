import AppKit
import FSearchKit
import Foundation
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

            // Open selected: doc opens & becomes recent; .app reveals instead of launching.
            SearchWindowActions.openSelected([docRow, appRow], app: env.app, onError: onError)
            #expect(env.workspace.opened == [URL(fileURLWithPath: docPath)])
            #expect(env.workspace.revealed == [[URL(fileURLWithPath: appPath)]])
            #expect(env.app.recents.paths.contains(docPath))

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

            // Trash succeeds and triggers refresh; failure reports error.
            await SearchWindowActions.trashSelected([docRow], app: env.app, onError: onError) { refreshes += 1 }
            #expect(env.workspace.trashed == [URL(fileURLWithPath: docPath)])
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
            #expect(SearchWindowView.rowShortcutsEnabled(searchFocused: false, popoverOpen: false, hasSelection: true))
            #expect(!SearchWindowView.rowShortcutsEnabled(searchFocused: true, popoverOpen: false, hasSelection: true))
            #expect(!SearchWindowView.rowShortcutsEnabled(searchFocused: false, popoverOpen: true, hasSelection: true))
            #expect(!SearchWindowView.rowShortcutsEnabled(searchFocused: false, popoverOpen: false, hasSelection: false))
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

            // SearchWindowContextMenu buttons route through SearchWindowActions.
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
            #expect(env.workspace.opened == [URL(fileURLWithPath: path)])
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
        }
    }
}
