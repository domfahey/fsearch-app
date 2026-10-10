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
        private func manager(_ helper: FakeHelper?, _ daemon: StubDaemon = StubDaemon(), cli: Bool = false, clock: FakeClock = FakeClock())
            -> DaemonManager
        {
            DaemonManager(client: daemon, service: helper, cliAgentInstalled: { cli }, clock: clock.clock)
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
            d.onPing = { _ in false }
            let m = manager(h, d, cli: true)
            await m.start()
            #expect(h.registered == 0)
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
    }
}
