import AppKit
import FSearchKit
import Foundation
import Quartz
import Testing

@testable import FSearch

extension AppTests {
    @Suite @MainActor
    struct FileActionsTests {
        private let line = ResultItem.line(path: "/p/main.swift", match: Match(line: 12, text: "func main()"))
        private let file = ResultItem.file(Wire.hit("/p/readme.md"))

        private let vscodeApp = URL(fileURLWithPath: "/Applications/Visual Studio Code.app")
        private func noErrors(_ m: String) { Issue.record("unexpected action error: \(m)") }

        @Test func editorTargetOnlyForInstalledEditorsAndLines() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            #expect(FileActions.editorTarget(for: file, editor: .vscode) == nil)
            #expect(FileActions.editorTarget(for: line, editor: nil) == nil)
            #expect(FileActions.editorTarget(for: line, editor: .vscode) == nil)  // not installed
            env.workspace.apps[Editor.vscode.bundleId] = vscodeApp
            env.workspace.schemeHandlers["vscode"] = [vscodeApp]
            let t = try #require(FileActions.editorTarget(for: line, editor: .vscode))
            #expect(t.url == Editor.vscode.openURL(path: "/p/main.swift", line: 12))
            #expect(t.app == vscodeApp)
            // Xcode has no open-at-line URL: the file, opened with Xcode.
            let xcode = URL(fileURLWithPath: "/Applications/Xcode.app")
            env.workspace.apps[Editor.xcode.bundleId] = xcode
            let x = try #require(FileActions.editorTarget(for: line, editor: .xcode))
            #expect(x.url == URL(fileURLWithPath: "/p/main.swift"))
            #expect(x.app == xcode)
        }

        @Test func openUsesTheDefaultApp() {
            let env = TestEnv()
            defer { env.tearDown() }
            #expect(FileActions.open(file, editor: nil, onError: noErrors))
            #expect(env.workspace.opened == [URL(fileURLWithPath: "/p/readme.md")])
            #expect(env.workspace.openedWith.isEmpty)
        }

        /// A-H1: the editor is opened by LaunchServices with its URL, so it
        /// never runs as FSearch's child (with FSearch's Full Disk Access).
        @Test func openLineInEditorThroughLaunchServices() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            env.workspace.apps[Editor.vscode.bundleId] = vscodeApp
            env.workspace.schemeHandlers["vscode"] = [vscodeApp]
            #expect(FileActions.open(line, editor: .vscode, onError: noErrors))
            #expect(env.workspace.openedWith.count == 1)
            #expect(env.workspace.openedWith.first?.app == vscodeApp)
            #expect(env.workspace.openedWith.first?.urls.map(\.absoluteString) == ["vscode://file/p/main.swift:12"])
            #expect(env.workspace.opened.isEmpty)
        }

        /// An editor that doesn't register its open-at-line scheme would never get the URL (and no error says so):
        /// it gets the file instead, without the line.
        @Test func anEditorWithoutItsSchemeGetsTheFile() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            env.workspace.apps[Editor.vscode.bundleId] = vscodeApp
            let fileURL = URL(fileURLWithPath: "/p/main.swift")
            for handlers in [[], [URL(fileURLWithPath: "/Applications/Other.app")]] {
                env.workspace.schemeHandlers["vscode"] = handlers
                let t = try #require(FileActions.editorTarget(for: line, editor: .vscode))
                #expect(t.url == fileURL && t.app == vscodeApp, "\(handlers)")
            }
            // The same app, spelled with a trailing slash, still counts.
            env.workspace.schemeHandlers["vscode"] = [URL(fileURLWithPath: vscodeApp.path + "/", isDirectory: true)]
            #expect(try #require(FileActions.editorTarget(for: line, editor: .vscode)).url.scheme == "vscode")
            #expect(FileActions.open(line, editor: .vscode, onError: noErrors))
            #expect(env.workspace.openedWith.first?.urls.first?.scheme == "vscode")
        }

        /// The footer asks what ↵ does on every redraw; the answer (LaunchServices, maybe the disk) is worked out once
        /// per selected row and editor.
        @Test func returnsActionIsCachedPerRowAndEditor() {
            let env = TestEnv()
            defer { env.tearDown() }
            let cache = RevealCache()
            #expect(!cache.revealsOnReturn(line, editor: .vscode))
            #expect(!cache.revealsOnReturn(line, editor: .vscode))
            #expect(env.workspace.appLookups == 1)
            #expect(!cache.revealsOnReturn(line, editor: .zed))
            #expect(env.workspace.appLookups == 2)
            #expect(cache.revealsOnReturn(.file(Wire.hit("/p/Tool.app")), editor: .zed))
            #expect(cache.revealsOnReturn(.file(Wire.hit("/p/Tool.app")), editor: .zed))
            #expect(!cache.revealsOnReturn(line, editor: nil))
        }

        @Test func editorThatFailsFallsBackToTheDefaultApp() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            env.workspace.apps[Editor.vscode.bundleId] = vscodeApp
            env.workspace.openWithError = TestError("no handler")
            #expect(FileActions.open(line, editor: .vscode, onError: noErrors))
            #expect(await eventually { env.workspace.opened == [URL(fileURLWithPath: "/p/main.swift")] })
        }

        /// Item 9: a result that is gone says so, and opens nothing.
        @Test func missingFileReportsAndOpensNothing() {
            let env = TestEnv()
            defer { env.tearDown() }
            env.workspace.missing = ["/p/readme.md", "/p/main.swift"]
            env.workspace.apps[Editor.vscode.bundleId] = vscodeApp
            var errors: [String] = []
            #expect(!FileActions.open(file, editor: nil) { errors.append($0) })
            #expect(!FileActions.open(line, editor: .vscode) { errors.append($0) })
            #expect(!FileActions.reveal("/p/readme.md") { errors.append($0) })
            FileActions.openWith("/p/readme.md", app: URL(fileURLWithPath: "/Applications/X.app")) { errors.append($0) }
            let readme = "“readme.md” is gone: moved or deleted", main = "“main.swift” is gone: moved or deleted"
            #expect(errors == [readme, main, readme, readme])
            #expect(env.workspace.opened.isEmpty)
            #expect(env.workspace.openedWith.isEmpty)
            #expect(env.workspace.revealed.isEmpty)
        }

        @Test func revealCopyAndOpenWith() {
            let env = TestEnv()
            defer { env.tearDown() }
            #expect(FileActions.reveal("/p/a b.txt", onError: noErrors))
            #expect(env.workspace.revealed == [[URL(fileURLWithPath: "/p/a b.txt")]])
            FileActions.copyPath("/p/🏡 a b.txt")
            #expect(env.pasteboard.string(forType: .string) == "/p/🏡 a b.txt")
            FileActions.copyFile("/p/a.txt")
            #expect(env.pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] == [URL(fileURLWithPath: "/p/a.txt")])
            FileActions.openWith("/p/a.txt", app: URL(fileURLWithPath: "/Applications/X.app"), onError: noErrors)
            #expect(env.workspace.openedWith.first?.app == URL(fileURLWithPath: "/Applications/X.app"))
            #expect(env.workspace.openedWith.first?.urls == [URL(fileURLWithPath: "/p/a.txt")])
        }

        /// Item 10: Open With reports a launch error, as Terminal does.
        @Test func openWithReportsErrors() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.workspace.openWithError = TestError("damaged")
            var errors: [String] = []
            FileActions.openWith("/p/a.txt", app: URL(fileURLWithPath: "/Applications/X.app")) { errors.append($0) }
            #expect(await eventually { errors == ["Couldn't open with X: damaged"] })
        }

        @Test func terminalOpensTheFolder() {
            let env = TestEnv()
            defer { env.tearDown() }
            let f = env.file("sub/x.txt")
            #expect(FileActions.terminalFolder(for: f) == env.dir.appendingPathComponent("sub").path)
            #expect(FileActions.terminalFolder(for: env.dir.path) == env.dir.path)
        }

        /// Item 11: a package (an app, an .rtfd) is a file to Terminal: its folder, not its insides.
        @Test func terminalTreatsAPackageAsAFile() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            for name in ["Tool.app", "Notes.rtfd"] {
                let pkg = env.dir.appendingPathComponent("sub/\(name)")
                try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
                #expect(FileActions.terminalFolder(for: pkg.path) == env.dir.appendingPathComponent("sub").path, "\(name)")
            }
            let dotted = env.dir.appendingPathComponent("v1.2")
            try FileManager.default.createDirectory(at: dotted, withIntermediateDirectories: true)
            #expect(FileActions.terminalFolder(for: dotted.path) == dotted.path)
        }

        @Test func terminalErrors() async {
            let env = TestEnv()
            defer { env.tearDown() }
            var errors: [String] = []
            FileActions.openTerminal(at: "/p/x.txt") { errors.append($0) }
            #expect(errors == ["Couldn't find Terminal"])

            env.workspace.apps["com.apple.Terminal"] = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
            FileActions.openTerminal(at: "/p/x.txt") { errors.append($0) }
            #expect(env.workspace.openedWith.first?.urls == [URL(fileURLWithPath: "/p")])
            #expect(errors.count == 1)

            env.workspace.openWithError = TestError("denied")
            FileActions.openTerminal(at: "/p/x.txt") { errors.append($0) }
            #expect(await eventually { errors.last == "Couldn't open Terminal: denied" })
        }

        /// A-M2: ↵ reveals what it would launch; documents open.
        @Test func returnRevealsLaunchableFiles() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            #expect(FileActions.revealsOnReturn(.file(Wire.hit("/p/Installer.pkg")), editor: nil))
            #expect(FileActions.revealsOnReturn(.file(Wire.hit("/p/run.command")), editor: nil))
            #expect(!FileActions.revealsOnReturn(file, editor: nil))
            // An extensionless file reveals only if it is executable.
            let tool = env.file("bin/tool", "#!/bin/sh\n")
            #expect(!FileActions.revealsOnReturn(.file(Wire.hit(tool)), editor: nil))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool)
            #expect(FileActions.revealsOnReturn(.file(Wire.hit(tool)), editor: nil))
            // A line in a script opens in the chosen editor, which runs nothing;
            // without an installed editor the default app would run it.
            let script = ResultItem.line(path: "/p/run.command", match: Match(line: 2, text: "echo"))
            #expect(FileActions.revealsOnReturn(script, editor: .vscode))
            env.workspace.apps[Editor.vscode.bundleId] = vscodeApp
            #expect(!FileActions.revealsOnReturn(script, editor: .vscode))
        }

        @Test func trashGoesThroughTheWorkspace() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            try FileActions.trash("/p/x.txt")
            #expect(env.workspace.trashed == [URL(fileURLWithPath: "/p/x.txt")])
            env.workspace.trashError = TestError()
            #expect(throws: TestError.self) { try FileActions.trash("/p/y.txt") }
        }

        /// UI tests' workspace: records every action, performs none.
        @Test func testModeWorkspaceOnlyRecords() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let log = TestModeWorkspace.logFile(socketPath: env.dir.path + "/sub/fsearch.sock")
            #expect(log.path == env.dir.path + "/sub/actions.log")
            let ws = TestModeWorkspace(log: log)
            let f = env.file("keep.txt")
            ws.open(URL(fileURLWithPath: f))
            ws.activateFileViewerSelecting([URL(fileURLWithPath: f)])
            ws.open([URL(fileURLWithPath: f)], withApplicationAt: URL(fileURLWithPath: "/Applications/X.app"), completion: nil)
            try ws.trash(URL(fileURLWithPath: f))
            ws.open(URL(string: "x-apple.systempreferences:x")!)
            let want = [
                "open \(f)", "reveal \(f)", "openWith X.app \(f)", "trash \(f)", "open x-apple.systempreferences:x",
            ]
            #expect(ws.actions == want)
            #expect(try String(contentsOf: log, encoding: .utf8) == want.joined(separator: "\n") + "\n")
            #expect(FileManager.default.fileExists(atPath: f))  // not trashed
            // File checks are real and read-only.
            #expect(ws.fileInfo(atPath: f) == FileInfo())
            #expect(ws.fileInfo(atPath: env.dir.path)?.isDirectory == true)
            #expect(ws.fileInfo(atPath: env.dir.path + "/nope") == nil)
        }

        /// In this host toggling only sets the item (no preview comes up); the
        /// data source then serves it.
        @Test func quickLookDataSource() {
            let q = QuickLookSource.shared
            let u = URL(fileURLWithPath: "/p/a b.txt")
            FileActions.quickLook(u.path)
            #expect(q.item == u)
            #expect(!q.isPreviewing)
            #expect(!QLPreviewPanel.sharedPreviewPanelExists() || !QLPreviewPanel.shared().isVisible)
            #expect(q.numberOfPreviewItems(in: nil) == 1)
            #expect((q.previewPanel(nil, previewItemAt: 0) as? URL) == u)
            q.close()  // nothing up: no-op
        }

        /// In the preview, ⌘Y closes it and ↑/↓ move the launcher's selection; extra modifiers make it no binding.
        @Test func previewKeys() {
            typealias Q = QuickLookSource
            #expect(Q.previewKey(characters: "y", modifiers: .command, keyCode: 0x10) == .close)
            #expect(Q.previewKey(characters: "Y", modifiers: .command, keyCode: 0x10) == .close)
            #expect(Q.previewKey(characters: "н", modifiers: .command, keyCode: 0x10) == .close)
            #expect(Q.previewKey(characters: "y", modifiers: [.command, .control], keyCode: 0x10) == nil)
            #expect(Q.previewKey(characters: "y", modifiers: [.command, .option], keyCode: 0x10) == nil)
            #expect(Q.previewKey(characters: "y", modifiers: [.command, .shift], keyCode: 0x10) == nil)
            #expect(Q.previewKey(characters: "y", modifiers: [], keyCode: 0x10) == nil)
            // Arrow keys carry the function and numeric-pad flags.
            let arrow: NSEvent.ModifierFlags = [.function, .numericPad]
            #expect(Q.previewKey(characters: "\u{F700}", modifiers: arrow, keyCode: 126) == .up)
            #expect(Q.previewKey(characters: "\u{F701}", modifiers: arrow, keyCode: 125) == .down)
            #expect(Q.previewKey(characters: "\u{F701}", modifiers: arrow.union(.command), keyCode: 125) == nil)
            #expect(Q.previewKey(characters: "\u{F701}", modifiers: arrow.union(.shift), keyCode: 125) == nil)
            #expect(Q.previewKey(characters: "\u{F702}", modifiers: arrow, keyCode: 123) == nil)  // ←
            #expect(Q.previewKey(characters: " ", modifiers: [], keyCode: 49) == nil)
        }

        /// ↑/↓ in the preview move the launcher's selection; ⌘Y closes.
        @Test func previewArrowsMoveTheLaunchersSelection() {
            let q = QuickLookSource.shared
            var moved: [PanelKey] = []
            let saved = q.move
            q.move = { moved.append($0) }
            defer { q.move = saved }
            q.handle(.down)
            q.handle(.up)
            q.handle(.close)  // nothing up: no-op
            #expect(moved == [.down, .up])
        }

        /// The preview follows the launcher's selection while it is up, and only then.
        @Test func previewFollowsTheSelection() {
            let q = QuickLookSource.shared
            let a = URL(fileURLWithPath: "/p/a.txt"), b = URL(fileURLWithPath: "/p/b.txt")
            q.toggle(a)
            q.follow(b)  // not previewing in this host: unchanged
            #expect(q.item == a)
            q.follow(b, previewing: true)
            #expect(q.item == b)
            q.follow(nil, previewing: true)  // a command or fallback row: keep the last file
            #expect(q.item == b)
            #expect(!QLPreviewPanel.sharedPreviewPanelExists() || !QLPreviewPanel.shared().isVisible)
        }

        /// Sent keys are numbered, so the same key twice is still a change the view sees.
        @Test func keyFeedNumbersEachKey() {
            let feed = PanelKeyFeed()
            #expect(feed.last == nil)
            feed.send(.down)
            feed.send(.down)
            #expect(feed.last == PanelKeyFeed.Sent(key: .down, n: 2))
        }
    }

    @Suite @MainActor
    struct ActionsMenuTests {
        private func run(_ item: NSMenuItem?) {
            (item?.representedObject as? ActionsMenu.Target)?.run(nil)
        }

        @Test func itemsWithoutOpenWithApps() {
            let env = TestEnv()
            defer { env.tearDown() }
            let menu = ActionsMenu.build(for: .file(Wire.hit("/p/x.txt")), app: env.app)
            #expect(
                menu.items.map(\.title) == [
                    "Open", "Open With", "Reveal in Finder", "Quick Look", "Copy Path", "Copy File", "Open Folder in Terminal", "",
                    "Move to Trash",
                ])
            #expect(menu.items[7].isSeparatorItem)
            #expect(!menu.autoenablesItems)
            #expect(menu.item(withTitle: "Open With")?.isEnabled == false)
            #expect(menu.item(withTitle: "Open With")?.submenu == nil)
            let others = menu.items.filter { !$0.isSeparatorItem && $0.title != "Open With" }
            #expect(others.allSatisfy { $0.isEnabled })
        }

        @Test func openWithListsUpToTwelveApps() {
            let env = TestEnv()
            defer { env.tearDown() }
            env.workspace.appsToOpen = (0..<15).map { URL(fileURLWithPath: "/Applications/App\($0).app") }
            let menu = ActionsMenu.build(for: .file(Wire.hit("/p/x.txt")), app: env.app)
            let with = menu.item(withTitle: "Open With")
            #expect(with?.isEnabled == true)
            #expect(with?.submenu?.items.count == 12)
            run(with?.submenu?.items.first)
            #expect(env.workspace.openedWith.first?.app == URL(fileURLWithPath: "/Applications/App0.app"))
        }

        @Test func eachItemRunsItsAction() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let path = env.file("x.txt")
            let menu = ActionsMenu.build(for: .file(Wire.hit(path)), app: env.app)
            let g = env.app.recentsGeneration
            run(menu.item(withTitle: "Open"))
            #expect(env.workspace.opened == [URL(fileURLWithPath: path)])
            #expect(env.app.recents.paths == [path])
            #expect(env.app.recentsGeneration == g + 1)
            run(menu.item(withTitle: "Reveal in Finder"))
            #expect(env.workspace.revealed.count == 1)
            run(menu.item(withTitle: "Copy Path"))
            #expect(env.pasteboard.string(forType: .string) == path)
            run(menu.item(withTitle: "Copy File"))
            #expect(env.pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] == [URL(fileURLWithPath: path)])
        }

        /// Item 9: Open on a file that is gone reports it, records no recent and keeps the launcher up.
        @Test func openOnAMissingFile() {
            let env = TestEnv()
            defer { env.tearDown() }
            env.workspace.missing = ["/p/gone.txt"]
            let menu = ActionsMenu.build(for: .file(Wire.hit("/p/gone.txt")), app: env.app)
            let g = env.app.recentsGeneration
            run(menu.item(withTitle: "Open"))
            #expect(env.app.actionError == "“gone.txt” is gone: moved or deleted")
            #expect(env.app.recentsGeneration == g)  // nothing recorded
            #expect(env.panel.hides == 0)
            run(menu.item(withTitle: "Reveal in Finder"))
            #expect(env.workspace.revealed.isEmpty)
            #expect(env.panel.hides == 0)
        }

        /// Item 10: an Open With launch error reaches the footer.
        @Test func openWithFailureShowsTheError() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.workspace.appsToOpen = [URL(fileURLWithPath: "/Applications/Preview.app")]
            env.workspace.openWithError = TestError("damaged")
            let menu = ActionsMenu.build(for: .file(Wire.hit("/p/x.txt")), app: env.app)
            run(menu.item(withTitle: "Open With")?.submenu?.items.first)
            #expect(await eventually { env.app.actionError == "Couldn't open with Preview: damaged" })
        }

        @Test func terminalFailureShowsTheError() {
            let env = TestEnv()
            defer { env.tearDown() }
            let menu = ActionsMenu.build(for: .file(Wire.hit("/p/x.txt")), app: env.app)
            run(menu.item(withTitle: "Open Folder in Terminal"))
            #expect(env.app.actionError == "Couldn't find Terminal")
            #expect(env.panel.shows == 1)
        }

        @Test func trash() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let menu = ActionsMenu.build(for: .file(Wire.hit("/p/x.txt")), app: env.app)
            let g = env.app.recentsGeneration
            run(menu.item(withTitle: "Move to Trash"))
            #expect(env.workspace.trashed == [URL(fileURLWithPath: "/p/x.txt")])
            #expect(env.app.recentsGeneration == g + 1)

            env.workspace.trashError = TestError("locked")
            run(menu.item(withTitle: "Move to Trash"))
            #expect(env.app.actionError == "Couldn't move to Trash: locked")
        }

        @Test func showPopsUpOnlyOverAPanel() {
            let env = TestEnv()
            defer { env.tearDown() }
            var shown: [[String]] = []
            let saved = ActionsMenu.popUp
            ActionsMenu.popUp = { menu, _, _ in shown.append(menu.items.map(\.title)) }
            defer { ActionsMenu.popUp = saved }
            ActionsMenu.show(for: .file(Wire.hit("/p/x.txt")), in: nil, app: env.app)
            #expect(shown.isEmpty)
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: true)
            panel.contentView = NSView()
            ActionsMenu.show(for: .file(Wire.hit("/p/x.txt")), in: panel, app: env.app)
            #expect(shown.first?.first == "Open")
            #expect(shown.first?.last == "Move to Trash")
        }

        /// ⌘K's menu opens under the selected row, or under the search field when the row is out of view.
        @Test func menuAnchorsAtTheSelectedRow() {
            let field = CGRect(x: 0, y: 0, width: 680, height: 50)
            let list = CGRect(x: 0, y: 60, width: 680, height: 360)
            let row = CGRect(x: 4, y: 100, width: 672, height: 34)
            let i = PanelGeometry.inset
            #expect(PanelGeometry.menuAnchor(row: row, list: list, field: field) == CGPoint(x: 4 + i, y: 134))
            // Cut off at the bottom of the list: the list's bottom edge.
            let low = CGRect(x: 4, y: 400, width: 672, height: 34)
            #expect(PanelGeometry.menuAnchor(row: low, list: list, field: field) == CGPoint(x: 4 + i, y: 420))
            // Scrolled out of view, or never laid out: under the search field.
            let gone = CGRect(x: 4, y: 500, width: 672, height: 34)
            #expect(PanelGeometry.menuAnchor(row: gone, list: list, field: field) == CGPoint(x: i, y: 50))
            #expect(PanelGeometry.menuAnchor(row: nil, list: list, field: field) == CGPoint(x: i, y: 50))

            let g = PanelGeometry()
            g.field = field
            g.list = list
            g.rows["/p/x.txt"] = row
            #expect(g.menuAnchor(rowID: "/p/x.txt") == CGPoint(x: 4 + i, y: 134))
            #expect(g.menuAnchor(rowID: "/p/other") == CGPoint(x: i, y: 50))
        }

        /// New rows for another query drop the old row frames, so a ⌘K held for
        /// them opens under the field rather than at a row's old place; the same
        /// query refreshed keeps them.
        @Test func newRowsDropOldRowFrames() {
            let g = PanelGeometry()
            g.list = CGRect(x: 0, y: 60, width: 680, height: 360)
            g.rows["/p/x.txt"] = CGRect(x: 4, y: 100, width: 672, height: 34)
            let a = PanelInput.Answer(query: "x", mode: .names, current: false)
            g.answerChanged(from: a, to: PanelInput.Answer(query: "x", mode: .names, current: true))
            #expect(g.rows.count == 1)
            g.answerChanged(from: a, to: PanelInput.Answer(query: "x", mode: .content, current: true))
            #expect(g.rows.isEmpty)
            g.rows["/p/x.txt"] = CGRect(x: 4, y: 100, width: 672, height: 34)
            g.answerChanged(from: a, to: PanelInput.Answer(query: "xy", mode: .names, current: true))
            #expect(g.rows.isEmpty)
            #expect(g.menuAnchor(rowID: "/p/x.txt") == CGPoint(x: PanelGeometry.inset, y: 50))
        }

        /// The anchor is measured from the top left; an unflipped view counts from the bottom.
        @Test func menuAnchorInViewCoordinates() {
            final class Flipped: NSView { override var isFlipped: Bool { true } }
            let plain = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 460))
            let flipped = Flipped(frame: plain.frame)
            #expect(PanelGeometry.viewPoint(CGPoint(x: 10, y: 100), in: flipped) == NSPoint(x: 10, y: 100))
            #expect(PanelGeometry.viewPoint(CGPoint(x: 10, y: 100), in: plain) == NSPoint(x: 10, y: 360))
        }

        @Test func showPopsUpAtTheSelectedRow() {
            let env = TestEnv()
            defer { env.tearDown() }
            var at: [NSPoint] = []
            let saved = ActionsMenu.popUp
            ActionsMenu.popUp = { _, p, _ in at.append(p) }
            defer { ActionsMenu.popUp = saved }
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 460), styleMask: [.borderless], backing: .buffered, defer: true)
            panel.contentView = NSView()
            let g = PanelGeometry()
            g.list = CGRect(x: 0, y: 60, width: 680, height: 360)
            g.rows["/p/x.txt"] = CGRect(x: 4, y: 100, width: 672, height: 34)
            ActionsMenu.show(for: .file(Wire.hit("/p/x.txt")), in: panel, app: env.app, geometry: g)
            #expect(at == [NSPoint(x: 4 + PanelGeometry.inset, y: 460 - 134)])
        }

        /// Like ↵, an action that sends you to another app puts the launcher
        /// away, unless it failed at once and its error line needs reading.
        @Test func erroredActionKeepsTheLauncherUp() {
            let env = TestEnv()
            defer { env.tearDown() }
            let path = env.file("x.txt")
            let menu = ActionsMenu.build(for: .file(Wire.hit(path)), app: env.app)
            run(menu.item(withTitle: "Copy Path"))
            #expect(env.panel.hides == 0)  // copying stays in the launcher
            run(menu.item(withTitle: "Open"))
            #expect(env.panel.hides == 1)
            run(menu.item(withTitle: "Open Folder in Terminal"))  // no Terminal: errors
            #expect(env.app.actionError == "Couldn't find Terminal")
            #expect(env.panel.hides == 1)
        }
    }
}
