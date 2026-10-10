import FSearchKit
import Foundation
import Testing
@testable import FSearch

extension AppTests {
    @Suite @MainActor
    struct LaunchOptionsTests {
        @Test func defaultsToTheRealSocket() {
            let o = LaunchOptions.parse(arguments: ["FSearch"], environment: [:], defaultSocket: "/real.sock")
            #expect(o == LaunchOptions(socketPath: "/real.sock", testMode: false, unitTestHost: false, showPanel: false))
            #expect(o.searchLogFile.path.hasSuffix("Library/Logs/FSearch/searches.jsonl"))
        }

        @Test func socketArgumentIsTestMode() {
            let o = LaunchOptions.parse(arguments: ["FSearch", "-UITestShowPanel", "-FSEARCH_SOCKET", "/t/h/x.sock"], environment: ["XCTestConfigurationFilePath": "/x"])
            #expect(o.socketPath == "/t/h/x.sock")
            #expect(o.testMode)
            #expect(!o.unitTestHost)  // a UI-test launch is the app proper
            #expect(o.showPanel)
            // The search log goes next to the test daemon, never to ~/Library/Logs.
            #expect(o.searchLogFile.path == "/t/h/searches.jsonl")
        }

        @Test func socketFlagWithoutAPath() {
            let o = LaunchOptions.parse(arguments: ["FSearch", "-FSEARCH_SOCKET"], environment: [:], defaultSocket: "/real.sock")
            #expect(o.testMode)
            #expect(o.socketPath == "/real.sock")
        }

        @Test(arguments: ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"])
        func xctestHostIsInert(key: String) {
            let o = LaunchOptions.parse(arguments: ["FSearch"], environment: [key: "1"], defaultSocket: "/real.sock")
            #expect(o.unitTestHost)
            #expect(o.testMode)
            #expect(o.socketPath != "/real.sock")
            #expect(o.socketPath.hasPrefix(NSTemporaryDirectory()))
        }

        /// The process running these tests is such a host: nothing real may start.
        @Test func thisProcessIsAnInertHost() {
            #expect(LaunchOptions.current.unitTestHost)
            #expect(LaunchOptions.current.testMode)
            #expect(!LaunchOptions.current.searchLogFile.path.contains("/Library/Logs/"))
        }
    }

    @Suite @MainActor
    struct AppStateTests {
        @Test func liveTestModeHasNoHelper() {
            let dir = NSTemporaryDirectory() + "fsa-live-\(UUID().uuidString.prefix(6))"
            let app = AppState.live(options: LaunchOptions(socketPath: dir + "/s.sock", testMode: true, unitTestHost: false, showPanel: false))
            #expect(app.daemon.service == nil)  // SMAppService is never touched
            #expect(!app.daemon.ownsDaemon)
            #expect(app.log.file.path == dir + "/searches.jsonl")
            #expect(app.options.testMode)
        }

        /// Test mode never touches the user's real com.domfahey.fsearch defaults.
        @Test func testModeUsesAThrowawayDefaultsSuite() {
            #expect(AppDefaults.make(testMode: false) === UserDefaults.standard)
            #expect(AppDefaults.store !== UserDefaults.standard)  // this host is test mode
            #expect(OnboardingLauncher.defaults !== UserDefaults.standard)
            let name = "com.domfahey.fsearch.apptests.\(UUID().uuidString)"
            defer { TestEnv.removeSuite(name) }
            UserDefaults(suiteName: name)!.set(["/stale"], forKey: "recentPaths")
            let d = AppDefaults.make(testMode: true, suiteName: name)
            #expect(d !== UserDefaults.standard)
            #expect(d.object(forKey: "recentPaths") == nil)  // emptied at launch
        }

        @Test func debugModeGatesTheSearchLog() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let app = env.app
            env.daemon.onSearch = { _ in SearchReply(tookUs: 1200, hits: [Wire.hit("/a/heron.txt")]) }
            #expect(!app.debugMode)
            app.search.query = "heron"
            await app.search.refresh()
            #expect(app.log.entries().isEmpty)

            app.debugMode = true
            #expect(env.defaults.bool(forKey: "debugMode"))
            await app.search.refresh()
            let rows = app.log.entries()
            #expect(rows.count == 1)
            #expect(rows.first?.query == "heron")
            #expect(rows.first?.results == 1)
            #expect(app.log.file.path.hasPrefix(env.dir.path))
            #expect(FileManager.default.fileExists(atPath: app.log.file.path))
        }

        @Test func editorIsStoredByRawValue() {
            let env = TestEnv()
            defer { env.tearDown() }
            #expect(env.app.editor == nil)
            env.app.editor = Editor.allCases.first
            #expect(env.app.editorRaw == Editor.allCases.first?.rawValue)
            #expect(env.defaults.string(forKey: "editor") == Editor.allCases.first?.rawValue)
            env.app.editor = nil
            #expect(env.app.editorRaw == "")
        }

        @Test func openingAFileMakesItRecent() {
            let env = TestEnv()
            defer { env.tearDown() }
            let f = env.file("doc.txt")
            let g = env.app.recentsGeneration
            env.app.openedRecent(f)
            #expect(env.app.recents.paths == [f])
            #expect(env.app.recentsGeneration == g + 1)
            env.app.recentsChanged()
            #expect(env.app.recentsGeneration == g + 2)
        }

        @Test func actionErrorBringsThePanelBackAndClears() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let app = env.app
            app.showActionError("Couldn't open")
            #expect(app.actionError == "Couldn't open")
            #expect(app.actionErrorCount == 1)
            #expect(env.panel.shows == 1)
            // Visible already: not shown again; the newer message wins.
            app.showActionError("second")
            #expect(env.panel.shows == 1)
            #expect(app.actionErrorCount == 2)
            #expect(app.actionError == "second")
            #expect(await eventually { app.actionError == nil })
        }

        @Test func defaultPanelHostIsTheLauncher() {
            let app = AppState(options: LaunchOptions(socketPath: "/nowhere.sock", testMode: true, unitTestHost: false, showPanel: false),
                               defaults: UserDefaults(suiteName: "com.domfahey.fsearch.apptests.panel")!, helper: nil,
                               names: StubDaemon(), content: StubDaemon(), control: StubDaemon())
            #expect(app.panel === PanelController.shared)
            TestEnv.removeSuite("com.domfahey.fsearch.apptests.panel")
        }
    }
}
