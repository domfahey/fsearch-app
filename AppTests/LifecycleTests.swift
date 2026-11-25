import AppKit
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

        /// "Isn't answering" never outlives the next results: the recovery check's throttle doesn't apply to it.
        @Test func resultsClearUnresponsiveAtOnce() async {
            let env = TestEnv(helper: FakeHelper(.enabled))
            defer { env.tearDown() }
            let app = env.app
            app.status = MenuBarStatus(defaults: env.defaults)
            let checked = app.status.recoveryCheck.shouldRefresh(daemonUnhealthy: true)
            #expect(checked, "a check just ran")
            app.searchSettled(.failed(.timeout))
            #expect(app.daemon.isUnresponsive)
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

        @Test func rapidDisconnectsWhileRestartingSpendOneBudgetToken() async {
            let gate = AsyncGate()
            let h = FakeHelper(.enabled)
            let d = StubDaemon()
            d.onPing = { _ in false }
            let clock = DaemonClock(
                now: { ContinuousClock.now },
                sleep: { _ in await gate.wait() })
            let env = TestEnv(helper: h, daemon: d)
            defer { env.tearDown() }
            let app = AppState(
                options: env.app.options, defaults: env.defaults, helper: h,
                names: d, content: d, control: d, clock: clock,
                cliAgentInstalled: { false }, socketHolder: { .ours })
            app.status = MenuBarStatus(defaults: env.defaults)
            // First disconnect starts a restart; two more while it's in flight spend no extra tokens.
            d.onStatus = { _ in throw DaemonError.disconnected }
            app.searchSettled(.failed(.disconnected))
            app.searchSettled(.failed(.disconnected))
            app.searchSettled(.failed(.disconnected))
            #expect(app.status.restartBudget.used == 1)
            d.onStatus = { _ in Wire.status() }
            gate.release()
            #expect(await eventually { h.registered == 1 })
        }

        @Test func rapidResultsWhileUnresponsiveCoalesceRecoveryRefresh() async {
            let gate = AsyncGate()
            let d = StubDaemon()
            let env = TestEnv(daemon: d)
            defer { env.tearDown() }
            let clock = DaemonClock(
                now: { ContinuousClock.now },
                sleep: { _ in await gate.wait() })
            let app = AppState(
                options: env.app.options, defaults: env.defaults, helper: nil,
                names: d, content: d, control: d, clock: clock, cliAgentInstalled: { false })
            app.status = MenuBarStatus(defaults: env.defaults)
            app.daemon.markUnresponsive()
            // First attempt fails so refresh() suspends on sleep(gate), keeping the refresh in flight.
            d.onStatus = { n in
                if n == 1 { throw DaemonError.timeout }
                return Wire.status()
            }
            app.searchSettled(.results)
            #expect(await eventually { d.statuses == 1 })
            app.searchSettled(.results)
            app.searchSettled(.results)
            try? await Task.sleep(for: .milliseconds(40))
            #expect(d.statuses == 1, "coalesced into one recovery refresh")
            gate.release()
            #expect(await eventually { !app.daemon.isUnresponsive })
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

        /// The copy in /Applications opens only once this process has quit (it would see this one and quit), however
        /// long quitting takes; no fixed delay.
        @Test func theMovedCopyOpensOnceThisProcessHasQuit() async throws {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fsa-mover-\(UUID().uuidString.prefix(8))")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let marker = dir.appendingPathComponent("opened")
            let quitting = Process()  // stands in for this app while it quits
            quitting.executableURL = URL(fileURLWithPath: "/bin/sleep")
            quitting.arguments = ["30"]
            try quitting.run()
            defer { if quitting.isRunning { quitting.terminate(); quitting.waitUntilExit() } }
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = InstallMover.relaunchArguments(
                app: marker, waitingFor: quitting.processIdentifier, open: "/usr/bin/touch")
            try relaunch.run()
            defer { if relaunch.isRunning { relaunch.terminate(); relaunch.waitUntilExit() } }
            try await Task.sleep(for: .milliseconds(1100))  // longer than the old fixed second
            #expect(!FileManager.default.fileExists(atPath: marker.path), "opened while the app was still running")
            quitting.terminate()
            quitting.waitUntilExit()
            #expect(await eventually { FileManager.default.fileExists(atPath: marker.path) })
            relaunch.waitUntilExit()
        }

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

        @Test func secondLaunchReopenNotificationShowsThePanel() {
            let env = TestEnv()
            defer { env.tearDown() }
            let center = NotificationCenter()
            LaunchGuards.observeReopen(panel: env.panel, app: env.app, center: center)
            defer { LaunchGuards.stopObservingReopen(center: center) }
            #expect(env.panel.shows == 0)
            LaunchGuards.notifyOtherInstance(center: center)
            #expect(env.panel.shows == 1 && env.panel.isVisible)
            // Already visible: don't re-show.
            LaunchGuards.notifyOtherInstance(center: center)
            #expect(env.panel.shows == 1)
        }

        @Test func testModeWorkspaceLogsNonFileURLsWithScheme() {
            let log = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fsa-tmw-\(UUID().uuidString.prefix(8)).log")
            defer { try? FileManager.default.removeItem(at: log) }
            let ws = TestModeWorkspace(log: log)
            let url = URL(string: "vscode://file/p/main.swift:42")!
            ws.open([url], withApplicationAt: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"), completion: nil)
            #expect(ws.actions == ["openWith Visual Studio Code.app vscode://file/p/main.swift:42"])
        }

        @Test func startAppOffersMoveOnBadLocationAndStartsNothing() {
            let env = TestEnv(helper: FakeHelper(.enabled))
            defer { env.tearDown() }
            let panel = PanelController()
            let delegate = AppDelegate()
            let actCenter = NotificationCenter(), reopenCenter = NotificationCenter()
            var offered: [InstallLocation.Problem] = []
            let badBundle = URL(fileURLWithPath: NSTemporaryDirectory() + "AppTranslocation/x/FSearch.app")
            LaunchGuards.startApp(
                state: env.app, delegate: delegate, panel: panel, bundleURL: badBundle,
                activationCenter: actCenter, reopenCenter: reopenCenter,
                offerMove: { offered.append($0) })
            #expect(offered == [.translocated])
            #expect(OnboardingLauncher.window == nil && !OnboardingLauncher.startedDaemon)
            #expect(!panel.isVisible)
        }

        @Test func startAppWiresPanelOnboardingObserversAndDelegate() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let panel = PanelController()
            defer { panel.hide(returnFocus: false) }
            let delegate = AppDelegate()
            let actCenter = NotificationCenter(), reopenCenter = NotificationCenter()
            defer {
                LaunchGuards.stopObservingActivation(center: actCenter)
                LaunchGuards.stopObservingReopen(center: reopenCenter)
            }
            var offered: [InstallLocation.Problem] = []
            LaunchGuards.startApp(
                state: env.app, delegate: delegate, panel: panel,
                activationCenter: actCenter, reopenCenter: reopenCenter,
                offerMove: { offered.append($0) })
            #expect(offered.isEmpty)
            #expect(OnboardingLauncher.startedDaemon)
            // Reopen notification reaches the panel installed by startApp.
            LaunchGuards.notifyOtherInstance(center: reopenCenter)
            #expect(panel.isVisible)
            panel.hide(returnFocus: false)
            // URL delegate was connected to the panel.
            let url = try #require(URL(string: "fsearch://search?q=heron"))
            delegate.application(NSApp, open: [url])
            #expect(panel.isVisible && env.app.search.query == "heron")
        }

        @Test func anotherCopyIsRunningNotifiesAndActivatesOtherInstance() {
            let real = LaunchOptions(socketPath: "/x.sock", testMode: false, unitTestHost: false, showPanel: false)
            let center = NotificationCenter()
            // Missing bundle id -> false.
            #expect(!LaunchGuards.anotherCopyIsRunning(options: real, center: center, bundleIdentifier: nil))
            // Live NSRunningApplication lookup sees only our own process -> false.
            #expect(!LaunchGuards.anotherCopyIsRunning(options: real, center: center))
            // Another instance running -> posts reopen notification, activates it, returns true.
            final class Counter: @unchecked Sendable { var n = 0 }
            let notified = Counter()
            var activated = 0
            let token = center.addObserver(forName: LaunchGuards.reopenNotification, object: nil, queue: nil) { _ in
                notified.n += 1
            }
            defer { center.removeObserver(token) }
            let me: pid_t = 100
            let found = LaunchGuards.anotherCopyIsRunning(
                options: real, center: center, bundleIdentifier: "com.domfahey.fsearch",
                runningApps: { _ in [(me, {}), (200, { activated += 1 })] }, me: me)
            #expect(found && notified.n == 1 && activated == 1)
        }

        @Test func offerMoveMovesOnFirstButtonAndSkipsMoveOnQuit() {
            let saved = AppActivation.activate
            var activations = 0
            AppActivation.activate = { activations += 1 }
            defer { AppActivation.activate = saved }

            var moved: [URL] = [], terminated = 0, titles: [String] = []
            LaunchGuards.offerMove(
                .translocated,
                runAlert: { alert in
                    #expect(alert.messageText == "Move FSearch to Applications")
                    #expect(alert.informativeText == InstallLocation.Problem.translocated.message)
                    titles = alert.buttons.map(\.title)
                    return .alertFirstButtonReturn
                },
                move: { moved.append($0) },
                terminate: { terminated += 1 })
            #expect(activations == 1)
            #expect(titles == ["Move to Applications", "Quit"])
            #expect(moved == [Bundle.main.bundleURL])
            #expect(terminated == 1)

            LaunchGuards.offerMove(
                .readOnlyVolume,
                runAlert: { _ in .alertSecondButtonReturn },
                move: { moved.append($0) },
                terminate: { terminated += 1 })
            #expect(activations == 2)
            #expect(moved.count == 1)
            #expect(terminated == 2)
        }
    }
}
