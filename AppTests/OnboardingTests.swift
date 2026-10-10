import AppKit
import FSearchKit
import Foundation
import SwiftUI
import Testing
@testable import FSearch

extension AppTests {
    @Suite @MainActor
    struct OnboardingLauncherTests {
        @Test func decisions() {
            #expect(OnboardingLauncher.decision(onboarded: false, testMode: false) == .showOnboarding)
            #expect(OnboardingLauncher.decision(onboarded: true, testMode: false) == .startDaemon)
            #expect(OnboardingLauncher.decision(onboarded: false, testMode: true) == .startDaemon)
            #expect(OnboardingLauncher.decision(onboarded: true, testMode: true) == .startDaemon)
        }

        @Test func testModeStartsTheDaemonWithoutAWindow() async {
            let env = TestEnv()
            defer { env.tearDown() }
            OnboardingLauncher.launch(app: env.app)
            #expect(OnboardingLauncher.window == nil)
            #expect(OnboardingLauncher.startedDaemon)
            #expect(await eventually { env.app.daemon.state == .running(Wire.status()) })
        }

        @Test func firstLaunchShowsOnboardingAndClosingStartsTheHelper() async {
            let env = TestEnv(helper: FakeHelper(.enabled))
            defer { env.tearDown() }
            OnboardingLauncher.launch(app: env.app)
            let w = OnboardingLauncher.window
            #expect(w?.title == "Welcome to FSearch")
            #expect(w?.isVisible == true)
            #expect(!OnboardingLauncher.startedDaemon)
            // Reopening brings back the same window.
            OnboardingLauncher.reopen(app: env.app)
            #expect(OnboardingLauncher.window === w)
            OnboardingLauncher.close()
            #expect(OnboardingLauncher.window == nil)
            #expect(OnboardingLauncher.startedDaemon)
            #expect(await eventually { env.app.daemon.state == .running(Wire.status()) })
        }

        @Test func closingAfterStep2DoesNotStartAgain() {
            let env = TestEnv(helper: FakeHelper(.enabled))
            defer { env.tearDown() }
            OnboardingLauncher.reopen(app: env.app)
            OnboardingLauncher.noteDaemonStarted()
            OnboardingLauncher.close()
            #expect(env.daemon.pings == 0)
        }

        @Test func onboardedNeverReopens() {
            let env = TestEnv(helper: FakeHelper(.enabled))
            defer { env.tearDown() }
            env.defaults.set(true, forKey: "onboarded")
            OnboardingLauncher.reopen(app: env.app)
            #expect(OnboardingLauncher.window == nil)
            OnboardingLauncher.launch(app: env.app)
            #expect(OnboardingLauncher.window == nil)
            #expect(OnboardingLauncher.startedDaemon)
        }
    }

    @Suite @MainActor
    struct OnboardingFlowTests {
        @Test func walksEveryStep() async {
            let env = TestEnv(helper: FakeHelper(.enabled))
            defer { env.tearDown() }
            var finished = false
            let flow = OnboardingFlow(app: env.app, defaults: env.defaults)
            flow.onFinish = { finished = true }
            #expect(flow.step == .welcome)
            #expect(flow.canContinue)
            await flow.poll()  // step 1 never talks to the daemon
            #expect(env.daemon.statuses == 0)

            flow.next()
            #expect(flow.step == .helper)
            #expect(flow.busy)
            #expect(await eventually { !flow.busy })
            #expect(flow.facts.helperEnabled)
            #expect(flow.entries == 42)
            #expect(flow.facts.indexReady)
            #expect(flow.daemonRunning)

            flow.next()
            #expect(flow.step == .fullDiskAccess)
            #expect(flow.canContinue)  // Full Disk Access is on
            flow.next()
            #expect(flow.step == .indexing)
            flow.next()
            #expect(env.defaults.bool(forKey: "onboarded"))
            #expect(finished)
        }

        @Test func fullDiskAccessButtons() {
            let env = TestEnv()
            defer { env.tearDown() }
            let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: .fullDiskAccess)
            flow.appeared()
            #expect(!flow.facts.skippedFullDiskAccess)
            #expect(!flow.canContinue)
            flow.turnOnFullDiskAccess()
            #expect(flow.pressedTurnOn)
            #expect(env.workspace.opened == [FDACopy.settingsURL])
            flow.openPrivacySettings()
            #expect(env.workspace.opened.count == 2)
            flow.skipFullDiskAccess()
            #expect(!flow.pressedTurnOn)
            #expect(flow.facts.skippedFullDiskAccess)
            #expect(env.defaults.bool(forKey: "skippedFullDiskAccess"))
            #expect(flow.canContinue)
            let again = OnboardingFlow(app: env.app, defaults: env.defaults)
            again.appeared()
            #expect(again.facts.skippedFullDiskAccess)
        }

        @Test func pollAppliesEveryDaemonState() async {
            let env = TestEnv(helper: FakeHelper(.requiresApproval))
            defer { env.tearDown() }
            let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: .helper)
            env.daemon.onStatus = { _ in throw DaemonError.indexing("indexing") }
            await flow.poll()
            #expect(env.app.daemon.state == .indexing)
            #expect(flow.facts.helperEnabled)
            #expect(flow.daemonRunning)

            env.daemon.onStatus = { _ in throw DaemonError.disconnected }
            await flow.poll()
            #expect(env.app.daemon.state == .needsApproval)
            #expect(!flow.facts.helperEnabled)
            // Awaiting approval: the poll leaves the daemon alone.
            let n = env.daemon.statuses
            await flow.poll()
            #expect(env.daemon.statuses == n)
        }

        @Test func failedStateKeepsFacts() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.daemon.onStatus = { _ in throw DaemonError.disconnected }
            let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: .helper)
            await flow.poll()
            #expect(env.app.daemon.state == .failed("The search helper isn't answering."))
            #expect(!flow.facts.helperEnabled)
            #expect(!flow.daemonRunning)
        }

        @Test func backFromSettingsRetriesApproval() async {
            let h = FakeHelper(.requiresApproval)
            let env = TestEnv(helper: h)
            defer { env.tearDown() }
            env.daemon.onPing = { _ in false }
            let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: .helper)
            await flow.returnedFromSettings()  // still checking: nothing to retry
            #expect(env.app.daemon.state == .checking)
            await env.app.daemon.start()
            #expect(env.app.daemon.state == .needsApproval)
            h.status = .enabled  // the user approved it
            await flow.returnedFromSettings()
            #expect(env.app.daemon.state == .running(Wire.status()))
            #expect(flow.facts.helperEnabled)
        }

        @Test func backFromSettingsRestartsOwnHelperOnce() async {
            let h = FakeHelper(.enabled)
            let env = TestEnv(helper: h)
            defer { env.tearDown() }
            env.daemon.onPing = { _ in false }
            env.daemon.onStatus = { _ in Wire.status(fullDiskAccess: false) }
            let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: .fullDiskAccess)
            await flow.poll()
            #expect(!flow.facts.fullDiskAccess)
            flow.turnOnFullDiskAccess()
            env.daemon.onStatus = { _ in Wire.status(fullDiskAccess: true) }
            await flow.returnedFromSettings()
            #expect(h.unregistered == 1)
            #expect(!flow.pressedTurnOn)
            #expect(flow.facts.fullDiskAccess)
            await flow.returnedFromSettings()
            #expect(h.unregistered == 1)
        }

        @Test func backFromSettingsOnWelcomeDoesNothing() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let flow = OnboardingFlow(app: env.app, defaults: env.defaults)
            await flow.returnedFromSettings()
            #expect(env.daemon.statuses == 0)
        }

        @Test func startCancelsAnInFlightPoll() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: .helper)
            env.daemon.onStatus = { n in if n == 1 { throw DaemonError.timeout }; return Wire.status() }
            let poll = Task { await flow.poll() }
            await Task.yield()
            await flow.startDaemon().value
            await poll.value
            #expect(env.app.daemon.state == .running(Wire.status()))
            #expect(!flow.busy)
        }

        @Test func viewRendersEveryStep() async {
            for (step, helper, status) in [
                (OnboardingStep.welcome, FakeHelper?.none, Wire.status()),
                (.helper, FakeHelper(.enabled), Wire.status()),
                (.helper, FakeHelper?.none, Wire.status()),
                (.fullDiskAccess, FakeHelper(.enabled), Wire.status(fullDiskAccess: false)),
                (.fullDiskAccess, FakeHelper?.none, Wire.status(fullDiskAccess: false)),
                (.fullDiskAccess, FakeHelper?.none, Wire.status()),
                (.indexing, FakeHelper?.none, Wire.status()),
            ] {
                let env = TestEnv(helper: helper)
                env.daemon.onStatus = { _ in status }
                await env.app.daemon.refresh()
                let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: step)
                flow.apply()
                let w = await render(OnboardingView(flow: flow).environmentObject(env.app), size: NSSize(width: 440, height: 300))
                #expect(w.contentView != nil)
                w.close()
                env.tearDown()
            }
        }

        @Test func helperStepShowsFailureAndApproval() async {
            for fail in [true, false] {
                let env = TestEnv(helper: FakeHelper(.notRegistered))
                env.daemon.onStatus = { _ in throw DaemonError.disconnected }
                if fail { await env.app.daemon.refresh() }
                let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: .helper)
                let w = await render(OnboardingView(flow: flow).environmentObject(env.app), size: NSSize(width: 440, height: 300))
                w.close()
                env.tearDown()
            }
        }
    }
}
