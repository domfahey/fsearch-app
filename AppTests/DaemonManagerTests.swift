import FSearchKit
import Foundation
import Testing

@testable import FSearch

/// Every app test shares globals (FileActions.workspace, MenuBarStatus.shared,
/// OnboardingLauncher), so the whole tree runs one test at a time.
@Suite(.serialized) @MainActor
struct AppTests {}

extension AppTests {
    @Suite @MainActor
    struct DaemonManagerTests {
        private func manager(
            _ helper: FakeHelper?, _ daemon: StubDaemon = StubDaemon(), cli: Bool = false, clock: FakeClock = FakeClock(),
            holder: @escaping () -> SocketHolder = { .none }, defaults: UserDefaults = TestEnv.emptySuite(TestEnv.unitSuite),
            identity: @escaping () -> String? = { nil }, granted: @escaping () -> Bool = { false }
        ) -> DaemonManager {
            DaemonManager(
                client: daemon, service: helper, cliAgentInstalled: { cli }, clock: clock.clock, socketHolder: holder,
                defaults: defaults, helperIdentity: identity, fullDiskAccessGranted: granted)
        }

        @Test func testModeOnlyRefreshesAndNeverOwns() async {
            let d = StubDaemon()
            let m = manager(nil, d)
            #expect(m.state == .checking)
            await m.start()
            #expect(m.state == .running(Wire.status()))
            #expect(!m.ownsDaemon)
            #expect(d.pings == 0)
            await m.restart()
            #expect(d.statuses == 2)
            m.openLoginItems()  // no helper: nothing to open
        }

        @Test func usesADaemonThatAlreadyAnswers() async {
            let h = FakeHelper(.notRegistered)
            let m = manager(h)
            await m.start()
            #expect(m.state == .running(Wire.status()))
            #expect(h.registered == 0)
            #expect(!m.ownsDaemon)
        }

        @Test func refreshesItsOwnEnabledHelper() async {
            let h = FakeHelper(.enabled)
            let d = StubDaemon()
            d.onPing = { _ in false }
            let m = manager(h, d)
            await m.start()
            #expect(m.state == .running(Wire.status()))
            #expect(m.ownsDaemon)
            #expect(h.registered == 0)
        }

        @Test func prefersARestartingCLIAgent() async {
            let h = FakeHelper(.notRegistered)
            let d = StubDaemon()
            // Back after ~5 s: within the CLI agent's 10 s window.
            d.onPing = { $0 >= 20 }
            let m = manager(h, d, cli: true)
            await m.start()
            #expect(h.registered == 0)
            #expect(m.state == .running(Wire.status()))
        }

        /// Item 17: a CLI plist with nothing behind it doesn't leave the app without a daemon.
        @Test func aLeftoverCLIPlistFallsBackToOurHelper() async {
            let h = FakeHelper(.notRegistered)
            let d = StubDaemon()
            d.onPing = { _ in false }
            let clock = FakeClock()
            let m = manager(h, d, cli: true, clock: clock)
            await m.start()
            #expect(clock.slept.filter { $0 == .milliseconds(250) }.count == 40)
            #expect(h.registered == 1)
            #expect(m.state == .running(Wire.status()))
        }

        @Test func waitingForApprovalDoesNotRegister() async {
            let h = FakeHelper(.requiresApproval)
            let d = StubDaemon()
            d.onPing = { _ in false }
            let m = manager(h, d)
            await m.start()
            #expect(m.state == .needsApproval)
            #expect(h.registered == 0)
        }

        @Test func recheckFindsADaemonComingBack() async {
            let h = FakeHelper(.notRegistered)
            let d = StubDaemon()
            d.onPing = { $0 >= 3 }
            let clock = FakeClock()
            let m = manager(h, d, clock: clock)
            await m.start()
            #expect(h.registered == 0)
            #expect(d.pings == 3)
            #expect(clock.slept == [.milliseconds(250), .milliseconds(250)])
            #expect(m.state == .running(Wire.status()))
        }

        @Test func registersAfterTheRecheckWindow() async {
            let h = FakeHelper(.notRegistered)
            let d = StubDaemon()
            d.onPing = { _ in false }
            let clock = FakeClock()
            let m = manager(h, d, clock: clock)
            await m.start()
            #expect(h.registered == 1)
            // 3 s of 250 ms pings.
            #expect(clock.slept.filter { $0 == .milliseconds(250) }.count == 12)
            #expect(m.ownsDaemon)
            #expect(m.state == .running(Wire.status()))
        }

        @Test func registeredButAwaitingApproval() async {
            let h = FakeHelper(.notRegistered)
            h.statusAfterRegister = .requiresApproval
            let d = StubDaemon()
            d.onPing = { _ in false }
            let m = manager(h, d)
            await m.start()
            #expect(m.state == .needsApproval)
        }

        @Test func registerFailureWhileAwaitingApproval() async {
            let h = FakeHelper(.notRegistered)
            h.registerError = TestError()
            h.statusOnFailure = .requiresApproval
            let d = StubDaemon()
            d.onPing = { _ in false }
            let m = manager(h, d)
            await m.start()
            #expect(m.state == .needsApproval)
        }

        @Test func registerFailureIsShown() async {
            let h = FakeHelper(.notRegistered)
            h.registerError = TestError("no helper")
            let d = StubDaemon()
            d.onPing = { _ in false }
            let m = manager(h, d)
            await m.start()
            #expect(m.state == .failed("Couldn't start the search helper: no helper"))
            #expect(d.statuses == 0)
        }

        @Test func startCancelledDuringRecheckLeavesStateAlone() async {
            let h = FakeHelper(.notRegistered)
            let d = StubDaemon()
            d.onPing = { _ in false }
            let m = manager(h, d)
            let t = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                await m.start()
            }
            await t.value
            #expect(m.state == .checking)
            #expect(h.registered == 0)
        }

        @Test func refreshReportsIndexing() async {
            let d = StubDaemon()
            d.onStatus = { _ in throw DaemonError.indexing("indexing 10%") }
            let m = manager(nil, d)
            await m.refresh()
            #expect(m.state == .indexing)
        }

        @Test func refreshRetriesThenFails() async {
            let d = StubDaemon()
            d.onStatus = { _ in throw DaemonError.disconnected }
            let clock = FakeClock()
            let m = manager(nil, d, clock: clock)
            await m.refresh()
            #expect(d.statuses == 50)
            #expect(clock.slept.count == 50)
            #expect(m.state == .failed("The search helper isn't answering."))
        }

        @Test func refreshRetriesUntilAnswered() async {
            let d = StubDaemon()
            d.onStatus = { n in
                if n < 4 { throw DaemonError.timeout }; return Wire.status(entries: 9)
            }
            let m = manager(nil, d)
            await m.refresh()
            #expect(m.state == .running(Wire.status(entries: 9)))
        }

        @Test func noAnswerWhileAwaitingApprovalStaysAwaiting() async {
            let h = FakeHelper(.requiresApproval)
            let d = StubDaemon()
            d.onStatus = { _ in throw DaemonError.disconnected }
            let m = manager(h, d)
            await m.refresh()
            #expect(m.state == .needsApproval)
        }

        @Test func cancelledRefreshLeavesStateAlone() async {
            let d = StubDaemon()
            d.onStatus = { _ in throw CancellationError() }
            let m = manager(nil, d)
            await m.refresh()
            #expect(m.state == .checking)

            d.onStatus = { _ in throw DaemonError.disconnected }
            let t = Task { @MainActor in
                withUnsafeCurrentTask { $0?.cancel() }
                await m.refresh()
            }
            await t.value
            #expect(m.state == .checking)
            #expect(d.statuses == 1)
        }

        @Test func refreshCancelledWhileRetrying() async {
            let d = StubDaemon()
            let m = manager(nil, d, clock: FakeClock())
            let t = Task { @MainActor in await m.refresh() }
            // The first answer fails and cancels the caller: the retry sleep sees it.
            d.onStatus = { _ in
                t.cancel(); throw DaemonError.timeout
            }
            await t.value
            #expect(m.state == .checking)
        }

        @Test func restartReregistersOnlyItsOwnHelper() async {
            let h = FakeHelper(.enabled)
            let d = StubDaemon()
            // The old daemon answers twice more, then goes away.
            d.onPing = { $0 <= 2 }
            let clock = FakeClock()
            let m = manager(h, d, clock: clock)
            await m.restart()
            #expect(h.unregistered == 1)
            #expect(h.registered == 1)
            #expect(clock.slept == [.milliseconds(100), .milliseconds(100)])
            #expect(m.state == .running(Wire.status()))
        }

        @Test func restartOfAnotherDaemonOnlyRefreshes() async {
            let h = FakeHelper(.notRegistered)
            let m = manager(h)
            await m.restart()
            #expect(h.unregistered == 0)
            #expect(m.state == .running(Wire.status()))
        }

        @Test func restartFailures() async {
            let h = FakeHelper(.enabled)
            h.registerError = TestError("gone")
            let d = StubDaemon()
            d.onPing = { _ in false }
            let m = manager(h, d)
            await m.restart()
            #expect(m.state == .failed("Couldn't start the search helper: gone"))

            let h2 = FakeHelper(.enabled)
            h2.statusAfterRegister = .requiresApproval
            let m2 = manager(h2, d)
            await m2.restart()
            #expect(m2.state == .needsApproval)
        }

        @Test func saveNowAndLoginItems() async {
            let h = FakeHelper()
            let d = StubDaemon()
            let m = manager(h, d)
            await m.saveNow()
            #expect(d.saves == 1)
            m.openLoginItems()
            #expect(h.openedSettings == 1)
        }

        @Test func liveClockSleeps() async throws {
            let c = DaemonClock.live
            let a = c.now()
            try await c.sleep(.milliseconds(5))
            #expect(c.now() > a)
        }

        @Test func cliAgentPlistIsOnlyAPath() {
            #expect(DaemonManager.cliAgentPlist.path.hasSuffix("Library/LaunchAgents/mt.nd.fsearch.plist"))
            #expect(DaemonManager.agentPlistName == "com.domfahey.fsearch.daemon.plist")
        }

        // MARK: ownership (item 18) and the never-take-over invariant

        @Test func ownershipComesFromTheSocketHolder() {
            let h = FakeHelper(.enabled)
            var holder = SocketHolder.ours
            let m = manager(h, holder: { holder })
            #expect(m.ownsDaemon)
            holder = .none  // our helper between restarts
            #expect(m.ownsDaemon)
            holder = .other  // our helper yielded to a CLI agent's daemon
            #expect(!m.ownsDaemon)
            h.status = .notRegistered
            holder = .ours
            #expect(!m.ownsDaemon)
        }

        /// The invariant: a running CLI daemon is never stopped, replaced or taken over,
        /// whether or not our login item is enabled, by restart or start.
        @Test(arguments: [DaemonPlan.ServiceStatus.enabled, .notRegistered, .requiresApproval, .notFound])
        func aRunningCLIDaemonIsAlwaysLeftAlone(own: DaemonPlan.ServiceStatus) async {
            let h = FakeHelper(own)
            let d = StubDaemon()  // the CLI daemon answers
            let m = manager(h, d, cli: true, holder: { .other })
            await m.start()
            await m.restart()
            await m.restart()
            #expect(h.unregistered == 0)
            #expect(h.registered == 0)
            #expect(!m.ownsDaemon)
            #expect(m.state == .running(Wire.status()))
        }

        /// Item 17: nothing answers and nothing is ours: restart starts one (after the recheck).
        @Test func restartWithNothingAnsweringStartsOne() async {
            let h = FakeHelper(.notRegistered)
            let d = StubDaemon()
            d.onPing = { _ in false }
            let m = manager(h, d)
            await m.restart()
            #expect(h.unregistered == 0)
            #expect(h.registered == 1)
            #expect(m.state == .running(Wire.status()))
        }

        /// Item 19: concurrent restarts share one unregister/register.
        @Test func concurrentRestartsAreSerialized() async {
            let h = FakeHelper(.enabled)
            let d = StubDaemon()
            d.onPing = { _ in false }
            let m = manager(h, d)
            async let a: Void = m.restart()
            async let b: Void = m.restart()
            async let c: Void = m.restart()
            _ = await (a, b, c)
            #expect(h.unregistered == 1)
            #expect(h.registered == 1)
            #expect(m.state == .running(Wire.status()))
            // Once it's done, a new restart runs again.
            await m.restart()
            #expect(h.unregistered == 2)
        }

        // MARK: item 15, a helper left running across an app update

        @Test func anUpdatedHelperOfOursIsRestartedOnce() async {
            let defaults = TestEnv.emptySuite(TestEnv.unitSuite)
            defer { _ = TestEnv.emptySuite(TestEnv.unitSuite) }
            defaults.set("1:10:5", forKey: DaemonManager.helperIdentityKey)
            let h = FakeHelper(.enabled)
            let m = manager(h, holder: { .ours }, defaults: defaults, identity: { "2:11:6" })
            await m.start()
            #expect(h.unregistered == 1)
            #expect(h.registered == 1)
            #expect(defaults.string(forKey: DaemonManager.helperIdentityKey) == "2:11:6")
            await m.start()
            #expect(h.unregistered == 1, "only once")
        }

        @Test func anUpdateNeverRestartsSomeoneElsesDaemon() async {
            let defaults = TestEnv.emptySuite(TestEnv.unitSuite)
            defer { _ = TestEnv.emptySuite(TestEnv.unitSuite) }
            defaults.set("1", forKey: DaemonManager.helperIdentityKey)
            let h = FakeHelper(.enabled)
            let m = manager(h, holder: { .other }, defaults: defaults, identity: { "2" })
            await m.start()
            #expect(h.unregistered == 0 && h.registered == 0)
            #expect(defaults.string(forKey: DaemonManager.helperIdentityKey) == "1")
        }

        @Test func aFreshlyRegisteredHelperIsOnlyRecorded() async {
            let defaults = TestEnv.emptySuite(TestEnv.unitSuite)
            defer { _ = TestEnv.emptySuite(TestEnv.unitSuite) }
            let h = FakeHelper(.notRegistered)
            let d = StubDaemon()
            d.onPing = { _ in false }
            let m = manager(h, d, defaults: defaults, identity: { "2" })
            await m.start()
            #expect(h.registered == 1 && h.unregistered == 0)
            #expect(defaults.string(forKey: DaemonManager.helperIdentityKey) == "2")
        }

        @Test func helperIdentityIsBuildSizeAndTime() throws {
            let f = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fsa-helper-\(UUID().uuidString.prefix(6))")
            defer { try? FileManager.default.removeItem(at: f) }
            try Data("abc".utf8).write(to: f)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1000)], ofItemAtPath: f.path)
            #expect(DaemonManager.helperIdentity(helper: f, build: "7") == "7:3:1000")
            #expect(DaemonManager.helperIdentity(helper: f, build: nil) == "?:3:1000")
            #expect(DaemonManager.helperIdentity(helper: f.appendingPathExtension("gone"), build: "7") == nil)
            // The unit-test host's bundle has no helper at all in some builds; either way no crash.
            _ = DaemonManager.bundledHelperIdentity()
        }

        // MARK: item 16, Full Disk Access granted from the menu

        @Test func aMenuGrantRestartsOurHelperOnReturn() async {
            let h = FakeHelper(.enabled)
            let d = StubDaemon()
            d.onStatus = { _ in Wire.status(fullDiskAccess: false) }
            d.onPing = { _ in false }
            let m = manager(h, d, holder: { .ours })
            await m.refresh()
            await m.appBecameActive()
            #expect(h.unregistered == 0, "not armed")
            m.armFullDiskAccessRestart()
            await m.appBecameActive()
            #expect(h.unregistered == 1)
            #expect(!m.fullDiskAccessRestartArmed)
            await m.appBecameActive()
            #expect(h.unregistered == 1, "once")
        }

        /// A menu-bar app isn't activated on return from System Settings, so the grant is looked for every 2 s while
        /// armed; seeing it restarts our helper then, not later in the middle of a search.
        @Test func aMenuGrantIsSeenWithoutActivation() async {
            let h = FakeHelper(.enabled)
            let d = StubDaemon()
            d.onStatus = { _ in Wire.status(fullDiskAccess: false) }
            d.onPing = { _ in false }
            let clock = FakeClock()
            var checks = 0
            let m = manager(
                h, d, clock: clock, holder: { .ours },
                granted: {
                    checks += 1; return checks >= 3
                })
            await m.refresh()
            m.armFullDiskAccessRestart()
            #expect(await eventually { h.unregistered == 1 })
            #expect(checks == 3 && !m.fullDiskAccessRestartArmed)
            #expect(clock.slept.filter { $0 == .seconds(2) }.count == 3)
            await m.appBecameActive()
            #expect(h.unregistered == 1, "once")
        }

        /// No grant in 2 minutes: the poll stops, and activation still restarts as before.
        @Test func theGrantPollGivesUpAfterTwoMinutes() async {
            let h = FakeHelper(.enabled)
            let d = StubDaemon()
            d.onStatus = { _ in Wire.status(fullDiskAccess: false) }
            d.onPing = { _ in false }
            var checks = 0
            let m = manager(
                h, d, holder: { .ours },
                granted: {
                    checks += 1; return false
                })
            await m.refresh()
            m.armFullDiskAccessRestart()
            #expect(await eventually { checks == 60 })
            try? await Task.sleep(for: .milliseconds(50))
            #expect(checks == 60 && h.unregistered == 0 && m.fullDiskAccessRestartArmed)
            await m.appBecameActive()
            #expect(h.unregistered == 1)
            _ = DaemonManager.appHasFullDiskAccess()  // read-only; whatever this host is granted
        }

        @Test func aMenuGrantNeverRestartsAnotherDaemonOrAWorkingOne() async {
            let h = FakeHelper(.enabled)
            let d = StubDaemon()
            d.onStatus = { _ in Wire.status(fullDiskAccess: false) }
            let other = manager(h, d, holder: { .other })
            await other.refresh()
            other.armFullDiskAccessRestart()
            await other.appBecameActive()
            #expect(h.unregistered == 0)

            d.onStatus = { _ in Wire.status(fullDiskAccess: true) }
            let granted = manager(h, d, holder: { .ours })
            await granted.refresh()
            granted.armFullDiskAccessRestart()
            await granted.appBecameActive()
            #expect(h.unregistered == 0)

            let unknown = manager(h, d, holder: { .ours })  // still .checking
            unknown.armFullDiskAccessRestart()
            await unknown.appBecameActive()
            #expect(h.unregistered == 0)
            #expect(!unknown.fullDiskAccessRestartArmed)
        }

        // MARK: item 30

        @Test func unresponsiveIsItsOwnFailure() async {
            let m = manager(nil)
            #expect(!m.isUnresponsive)
            m.markUnresponsive()
            #expect(m.isUnresponsive)
            #expect(MenuBarStatus.condition(m.state) == .unresponsive)
            #expect(MenuBarStatus.condition(.failed("other")) == .failed)
            await m.refresh()
            #expect(!m.isUnresponsive)
        }
    }
}
