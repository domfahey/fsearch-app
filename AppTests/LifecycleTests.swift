import FSearchKit
import Foundation
import Testing

@testable import FSearch

extension AppTests {
    /// Audit round 2, lifecycle: restarts budget, test hooks, menu windows,
    /// the update reminder, the indexing poll and launch guards.
    @Suite @MainActor
    struct LifecycleTests {
        // MARK: item 30

        @Test func outOfRestartsTheHelperIsUnresponsive() async {
            let env = TestEnv(helper: FakeHelper(.enabled))
            defer { env.tearDown() }
            let app = env.app
            app.status = MenuBarStatus(defaults: env.defaults)
            for _ in 0..<app.status.restartBudget.max { _ = app.status.restartBudget.spend() }
            app.searchSettled(.failed(.disconnected))
            #expect(app.daemon.isUnresponsive)
            #expect(env.helper?.unregistered == 0, "no restart left to spend")
            // Results again: the budget refills and the recovery check clears it.
            app.searchSettled(.results)
            #expect(await eventually { !app.daemon.isUnresponsive })
        }

        @Test func aTimeoutIsUnresponsive() {
            let env = TestEnv()
            defer { env.tearDown() }
            env.app.status = MenuBarStatus(defaults: env.defaults)
            env.app.searchSettled(.failed(.timeout))
            #expect(env.app.daemon.isUnresponsive)
        }

        // MARK: A-L3

        @Test func releaseBuildsIgnoreTheTestHooks() {
            let o = LaunchOptions.parse(
                arguments: ["FSearch", "-FSEARCH_SOCKET", "/evil.sock", "-UITestShowPanel"],
                environment: ["XCTestSessionIdentifier": "x"], defaultSocket: "/real.sock", honorsTestHooks: false)
            #expect(o == LaunchOptions(socketPath: "/real.sock", testMode: false, unitTestHost: false, showPanel: false))
            // This (Debug) build honours them; that's what lets the tests run at all.
            #expect(LaunchOptions.testHooksCompiledIn)
        }

        // MARK: item 21

        @Test func menuWindowsActivateBeforeOpening() {
            let saved = AppActivation.activate
            defer { AppActivation.activate = saved }
            var calls: [String] = []
            AppActivation.activate = { calls.append("activate") }
            MenuWindows.open("index") { calls.append("open \($0)") }
            MenuWindows.openSettings { calls.append("settings") }
            #expect(calls == ["activate", "open index", "activate", "settings"])
        }

        // MARK: item 16 (the menu side)

        @Test func theMenusFullDiskAccessItemArmsARestartOnlyForOurHelper() {
            let env = TestEnv(helper: FakeHelper(.enabled))
            defer { env.tearDown() }
            FullDiskAccessReminder.turnOn(daemon: env.app.daemon)
            #expect(env.app.daemon.fullDiskAccessRestartArmed)
            #expect(env.workspace.opened.count == 1)

            let other = TestEnv()  // test mode: never ours
            defer { other.tearDown() }
            FullDiskAccessReminder.turnOn(daemon: other.app.daemon)
            #expect(!other.app.daemon.fullDiskAccessRestartArmed)
            #expect(other.workspace.opened.count == 1)
        }

        // MARK: item 22

        @Test func theUpdateReminderSurvivesARelaunch() {
            let defaults = TestEnv.emptySuite(TestEnv.unitSuite)
            defer { _ = TestEnv.emptySuite(TestEnv.unitSuite) }
            let before = UpdateReminderModel(defaults: defaults)
            before.update { $0.willShow(bySparkle: false, userInitiated: false) }
            #expect(defaults.bool(forKey: UpdateReminderModel.persistKey))

            let after = UpdateReminderModel(defaults: defaults)  // the next launch
            var checks = 0
            Updater.resumeReminder(model: after, updaterRunning: false) { checks += 1 }
            #expect(checks == 0, "no updater, nothing to ask")
            Updater.resumeReminder(model: after, updaterRunning: true) { checks += 1 }
            #expect(checks == 1)
            #expect(!after.persistedVisible, "asked once")
            Updater.resumeReminder(model: after, updaterRunning: true) { checks += 1 }
            #expect(checks == 1)

            after.update { $0.willShow(bySparkle: false, userInitiated: false) }
            after.update { $0.sessionWillFinish() }
            #expect(!after.persistedVisible)
        }

        // MARK: item 3

        @Test func theIndexingPollStopsWhileHidden() async {
            var steps = 0, sleeps = 0
            var visible = true
            await DaemonMessageLine.pollWhileIndexing(
                isIndexing: { true }, visible: { visible }, sleep: { sleeps += 1 },
                step: {
                    steps += 1
                    if steps == 3 { visible = false }
                })
            #expect(steps == 3)
            #expect(sleeps == 4, "one more wait, then it sees the hidden panel and stops")
        }

        @Test func theIndexingPollIsCappedAndEndsWithIndexing() async {
            var steps = 0
            await DaemonMessageLine.pollWhileIndexing(
                isIndexing: { true }, visible: { true }, sleep: {}, step: { steps += 1 }, maxTries: 5)
            #expect(steps == 5)
            steps = 0
            await DaemonMessageLine.pollWhileIndexing(
                isIndexing: { steps < 2 }, visible: { true }, sleep: {}, step: { steps += 1 })
            #expect(steps == 2)
        }

        // MARK: item 20

        @Test func anEmptyDaemonLogExplainsItself() {
            #expect(IndexDetailsView.logText("") == IndexDetailsView.noLogNote)
            #expect(IndexDetailsView.noLogNote.contains("daemon.log"))
            #expect(IndexDetailsView.logText("line 1") == "line 1")
        }

        // MARK: item 24 and A-M3

        @Test func launchGuardsStandDownInTestMode() {
            let test = LaunchOptions(socketPath: "/x.sock", testMode: true, unitTestHost: true, showPanel: false)
            #expect(!LaunchGuards.anotherCopyIsRunning(options: test))
            #expect(LaunchGuards.installProblem(options: test, bundleURL: URL(fileURLWithPath: "/Volumes/X/FSearch.app")) == nil)
            // Outside test mode, a writable, untranslocated folder is fine.
            let real = LaunchOptions(socketPath: "/x.sock", testMode: false, unitTestHost: false, showPanel: false)
            #expect(LaunchGuards.installProblem(options: real, bundleURL: URL(fileURLWithPath: NSTemporaryDirectory())) == nil)
            #expect(
                LaunchGuards.installProblem(
                    options: real, bundleURL: URL(fileURLWithPath: NSTemporaryDirectory() + "AppTranslocation/x/FSearch.app"))
                    == .translocated)
        }
    }
}
