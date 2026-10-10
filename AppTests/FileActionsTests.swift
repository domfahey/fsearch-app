import AppKit
import FSearchKit
import Foundation
import Testing
@testable import FSearch

extension AppTests {
    @Suite @MainActor
    struct FileActionsTests {
        private let line = ResultItem.line(path: "/p/main.swift", match: Match(line: 12, text: "func main()"))
        private let file = ResultItem.file(Wire.hit("/p/readme.md"))

        @Test func editorCommandOnlyForInstalledEditorsAndLines() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let editor = try #require(Editor.allCases.first)
            #expect(FileActions.editorCommand(for: file, editor: editor) == nil)
            #expect(FileActions.editorCommand(for: line, editor: nil) == nil)
            #expect(FileActions.editorCommand(for: line, editor: editor) == nil)  // not installed
            env.workspace.apps[editor.bundleId] = URL(fileURLWithPath: "/Applications/Ed.app")
            let c = try #require(FileActions.editorCommand(for: line, editor: editor))
            #expect(c == openAtLine(editor, appURL: URL(fileURLWithPath: "/Applications/Ed.app"), path: "/p/main.swift", line: 12))
        }

        @Test func openUsesTheDefaultApp() {
            let env = TestEnv()
            defer { env.tearDown() }
            FileActions.open(file, editor: nil)
            #expect(env.workspace.opened == [URL(fileURLWithPath: "/p/readme.md")])
            #expect(env.workspace.runs.isEmpty)
        }

        @Test func openLineInEditor() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let editor = try #require(Editor.allCases.first)
            env.workspace.apps[editor.bundleId] = URL(fileURLWithPath: "/Applications/Ed.app")
            FileActions.open(line, editor: editor)
            #expect(env.workspace.runs.count == 1)
            #expect(env.workspace.opened.isEmpty)
        }

        @Test func editorThatWontStartFallsBack() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let editor = try #require(Editor.allCases.first)
            env.workspace.apps[editor.bundleId] = URL(fileURLWithPath: "/Applications/Ed.app")
            env.workspace.runStarts = false
            FileActions.open(line, editor: editor)
            #expect(env.workspace.opened == [URL(fileURLWithPath: "/p/main.swift")])
        }

        @Test func editorThatFailsFallsBack() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let editor = try #require(Editor.allCases.first)
            env.workspace.apps[editor.bundleId] = URL(fileURLWithPath: "/Applications/Ed.app")
            env.workspace.runExitStatus = 2
            FileActions.open(line, editor: editor)
            #expect(await eventually { env.workspace.opened == [URL(fileURLWithPath: "/p/main.swift")] })
        }

        @Test func revealCopyAndOpenWith() {
            let env = TestEnv()
            defer { env.tearDown() }
            FileActions.reveal("/p/a b.txt")
            #expect(env.workspace.revealed == [[URL(fileURLWithPath: "/p/a b.txt")]])
            FileActions.copyPath("/p/🏡 a b.txt")
            #expect(env.pasteboard.string(forType: .string) == "/p/🏡 a b.txt")
            FileActions.copyFile("/p/a.txt")
            #expect(env.pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] == [URL(fileURLWithPath: "/p/a.txt")])
            FileActions.openWith("/p/a.txt", app: URL(fileURLWithPath: "/Applications/X.app"))
            #expect(env.workspace.openedWith.first?.app == URL(fileURLWithPath: "/Applications/X.app"))
        }

        @Test func terminalOpensTheFolder() {
            let env = TestEnv()
            defer { env.tearDown() }
            let f = env.file("sub/x.txt")
            #expect(FileActions.terminalFolder(for: f) == env.dir.appendingPathComponent("sub").path)
            #expect(FileActions.terminalFolder(for: env.dir.path) == env.dir.path)
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

        @Test func trashGoesThroughTheWorkspace() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            try FileActions.trash("/p/x.txt")
            #expect(env.workspace.trashed == [URL(fileURLWithPath: "/p/x.txt")])
            env.workspace.trashError = TestError()
            #expect(throws: TestError.self) { try FileActions.trash("/p/y.txt") }
        }

        @Test func quickLookDataSource() {
            let q = QuickLookSource.shared
            #expect(!q.isPreviewing)
            q.close()  // nothing up: no-op
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
            #expect(menu.items.map(\.title) == ["Open", "Open With", "Reveal in Finder", "Quick Look", "Copy Path", "Copy File", "Open Folder in Terminal", "", "Move to Trash"])
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

        @Test func showWithoutAPanelDoesNothing() {
            let env = TestEnv()
            defer { env.tearDown() }
            ActionsMenu.show(for: .file(Wire.hit("/p/x.txt")), in: nil, app: env.app)
        }
    }
}
