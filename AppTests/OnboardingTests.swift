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

        @Test func closingAfterStep2DoesNotStartAgain() async {
            let env = TestEnv(helper: FakeHelper(.enabled))
            defer { env.tearDown() }
            OnboardingLauncher.reopen(app: env.app)
            OnboardingLauncher.noteDaemonStarted()
            OnboardingLauncher.close()
            #expect(OnboardingLauncher.window == nil)
            // A start would be a Task: give one time to run before checking none did.
            try? await Task.sleep(for: .milliseconds(100))
            #expect(env.daemon.pings == 0)
            #expect(env.daemon.statuses == 0)
            #expect(env.app.daemon.state == .checking)
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

        @Test func resetClosesAnOpenWindowWithoutStartingTheDaemon() async {
            let env = TestEnv(helper: FakeHelper(.enabled))
            defer { env.tearDown() }
            OnboardingLauncher.launch(app: env.app)
            #expect(OnboardingLauncher.window != nil)
            OnboardingLauncher.reset()
            #expect(OnboardingLauncher.window == nil && !OnboardingLauncher.startedDaemon)
            try? await Task.sleep(for: .milliseconds(50))
            #expect(env.daemon.pings == 0 && env.daemon.statuses == 0)
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
            let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: .helper)
            await flow.poll()
            #expect(flow.facts.helperEnabled)
            env.daemon.onStatus = { _ in throw DaemonError.disconnected }
            await flow.poll()
            #expect(env.app.daemon.state == .failed("The background helper isn't answering."))
            #expect(!flow.facts.helperEnabled)
            #expect(!flow.daemonRunning)
        }

        @Test func activationDoesNotReinstallARemovedHelper() async throws {
            let h = FakeHelper(.requiresApproval)
            let env = TestEnv(helper: h)
            defer { env.tearDown() }
            env.daemon.onPing = { _ in false }
            let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: .helper)
            await env.app.daemon.start()
            #expect(env.app.daemon.state == .needsApproval)
            await env.app.daemon.suspendForRemoval()
            try await h.unregister()
            env.app.daemon.finishRemoval()
            #expect(env.app.daemon.recoverySuspended)
            await flow.returnedFromSettings()
            #expect(h.registered == 0)
            #expect(env.app.daemon.recoverySuspended)
            #expect(env.app.daemon.state == .needsApproval)
            // The helper step is the explicit setup action and still resumes.
            await flow.startDaemon().value
            #expect(h.registered == 1)
            #expect(!env.app.daemon.recoverySuspended)
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
            // Each answer carries its call number: the last call is start()'s, and
            // a stale poll publishing after it would show an earlier number.
            env.daemon.onStatus = { n in
                if n == 1 { throw DaemonError.timeout }; return Wire.status(entries: n)
            }
            let poll = Task { await flow.poll() }
            await Task.yield()
            await flow.startDaemon().value
            await poll.value
            let last = env.daemon.statuses
            #expect(last >= 2)
            #expect(env.app.daemon.state == .running(Wire.status(entries: last)))
            #expect(flow.entries == last)
            #expect(!flow.busy)
        }

        /// Render smoke test of every step and branch; asserts which branch each
        /// case renders (SwiftUI's text isn't readable in-process).
        @Test func viewRendersEveryStep() async {
            // The branch each step's view shows, from the same inputs the view reads.
            func branch(_ f: OnboardingFlow) -> String {
                let owns = f.app.daemon.ownsDaemon
                switch f.step {
                case .welcome: return "welcome"
                case .helper:
                    if Onboarding.helperStepMode(owns: owns, running: f.daemonRunning) == .existingDaemon { return "existing daemon" }
                    return f.facts.helperEnabled ? "allowed" : "ask"
                case .fullDiskAccess:
                    let mode = Onboarding.fullDiskAccessStepMode(
                        owns: owns, running: f.daemonRunning, fullDiskAccess: f.facts.fullDiskAccess)
                    return "\(mode)"
                case .indexing: return "indexing \(f.entries)"
                }
            }
            for (step, helper, status, want) in [
                (OnboardingStep.welcome, FakeHelper?.none, Wire.status(), "welcome"),
                (.helper, FakeHelper(.enabled), Wire.status(), "allowed"),
                (.helper, FakeHelper?.none, Wire.status(), "existing daemon"),
                (.fullDiskAccess, FakeHelper(.enabled), Wire.status(fullDiskAccess: false), "bundledHelper"),
                (.fullDiskAccess, FakeHelper?.none, Wire.status(fullDiskAccess: false), "existingDaemon"),
                (.fullDiskAccess, FakeHelper?.none, Wire.status(), "granted"),
                (.indexing, FakeHelper?.none, Wire.status(), "indexing 42"),
            ] {
                let env = TestEnv(helper: helper)
                defer { env.tearDown() }
                env.daemon.onStatus = { _ in status }
                await env.app.daemon.refresh()
                let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: step)
                flow.apply()
                let w = await render(OnboardingView(flow: flow).environmentObject(env.app), size: NSSize(width: 440, height: 300))
                #expect(branch(flow) == want, "\(step)")
                w.close()
            }
        }

        @Test func helperStepShowsFailureAndApproval() async {
            for fail in [true, false] {
                let env = TestEnv(helper: FakeHelper(.notRegistered))
                defer { env.tearDown() }
                env.daemon.onStatus = { _ in throw DaemonError.disconnected }
                if fail { await env.app.daemon.refresh() }
                // Otherwise the view's own poll must leave it checking.
                if !fail { env.daemon.onStatus = { _ in throw CancellationError() } }
                let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: .helper)
                let w = await render(OnboardingView(flow: flow).environmentObject(env.app), size: NSSize(width: 440, height: 300))
                defer { w.close() }
                // The inputs that pick "failed: Try Again" vs "Open Login Items Settings".
                #expect(Onboarding.helperStepMode(owns: env.app.daemon.ownsDaemon, running: flow.daemonRunning) == .bundledHelper)
                #expect(!flow.facts.helperEnabled && !flow.busy)
                #expect(env.app.daemon.state == (fail ? .failed("The background helper isn't answering.") : .checking))
                if !fail {
                    // While still checking, don't flash "Open Login Items Settings".
                    #expect(await eventually { !axTexts(in: w).isEmpty })
                    #expect(!axTexts(in: w).contains("Open Login Items Settings"))
                }
            }
        }

        @Test func indexingStepShowsReadyStateOnceIndexed() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.daemon.onStatus = { _ in Wire.status(entries: 42) }
            await env.app.daemon.refresh()
            let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: .indexing)
            flow.apply()
            #expect(flow.facts.indexReady)
            let w = await render(OnboardingView(flow: flow).environmentObject(env.app), size: NSSize(width: 440, height: 300))
            defer { w.close() }
            #expect(await eventually { !axTexts(in: w).isEmpty })
            #expect(!axTexts(in: w).contains("Indexing your disk"))
        }

        @Test func fullDiskAccessPollRestartsOwnedHelperWhenGrantAppears() async {
            let h = FakeHelper(.enabled)
            let d = StubDaemon()
            d.onPing = { _ in false }
            d.onStatus = { _ in Wire.status(fullDiskAccess: false) }
            let env = TestEnv(helper: h, daemon: d)
            defer { env.tearDown() }
            var granted = false
            let app = AppState(
                options: env.app.options, defaults: env.defaults, helper: h,
                names: d, content: d, control: d, clock: env.clock.clock,
                cliAgentInstalled: { false }, socketHolder: { .ours }, fullDiskAccessGranted: { granted })
            let flow = OnboardingFlow(app: app, defaults: env.defaults, step: .fullDiskAccess)
            await flow.poll()
            flow.turnOnFullDiskAccess()
            granted = true
            d.onStatus = { _ in Wire.status(fullDiskAccess: true) }
            await flow.poll()
            #expect(h.unregistered == 1)
            #expect(!flow.pressedTurnOn)
            #expect(flow.facts.fullDiskAccess)
        }

        @Test func pollForwardsTaskCancellationToInFlightRefresh() async {
            let gate = AsyncGate()
            let d = StubDaemon()
            d.onStatus = { _ in throw DaemonError.timeout }
            let env = TestEnv(daemon: d)
            defer { env.tearDown() }
            let clock = DaemonClock(
                now: { ContinuousClock.now },
                sleep: { _ in
                    await gate.wait()
                    try Task.checkCancellation()
                })
            let app = AppState(
                options: env.app.options, defaults: env.defaults, helper: nil,
                names: d, content: d, control: d, clock: clock, cliAgentInstalled: { false })
            let flow = OnboardingFlow(app: app, defaults: env.defaults, step: .helper)
            let pollTask = Task { await flow.poll() }
            #expect(await eventually { d.statuses == 1 })
            pollTask.cancel()
            gate.release()
            await pollTask.value
            #expect(app.daemon.state == .checking, "cancelled poll must not publish a stale result")
        }

        @Test func welcomeStepShowsHotkeyConflictWarning() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: .welcome)
            let w = await render(
                OnboardingView(flow: flow, runningBundleIds: { ["com.raycast.macos"] }).environmentObject(env.app),
                size: NSSize(width: 440, height: 300))
            defer { w.close() }
            #expect(await eventually { axTexts(in: w).contains { $0.contains("Raycast") } })
        }

        @Test func helperStepButtonsRetryFailureAndOpenLoginItems() async throws {
            let helper = FakeHelper(.enabled)
            let env = TestEnv(helper: helper)
            defer { env.tearDown() }
            env.daemon.onStatus = { _ in throw DaemonError.disconnected }
            await env.app.daemon.refresh()
            let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: .helper)
            let w = await render(OnboardingView(flow: flow).environmentObject(env.app), size: NSSize(width: 440, height: 300))
            defer { w.close() }
            env.daemon.onStatus = { _ in Wire.status() }
            try #require(await axWait("Try Again", in: w)).press()
            #expect(await eventually { flow.facts.helperEnabled })

            let approvalHelper = FakeHelper(.requiresApproval)
            let env2 = TestEnv(helper: approvalHelper)
            defer { env2.tearDown() }
            env2.daemon.onPing = { _ in false }
            await env2.app.daemon.start()
            let flow2 = OnboardingFlow(app: env2.app, defaults: env2.defaults, step: .helper)
            let w2 = await render(OnboardingView(flow: flow2).environmentObject(env2.app), size: NSSize(width: 440, height: 300))
            defer { w2.close() }
            try #require(await axWait("Open Login Items Settings", in: w2)).press()
            #expect(approvalHelper.openedSettings == 1)
            // Becoming active while approved retries automatically.
            approvalHelper.status = .enabled
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
            #expect(await eventually { flow2.facts.helperEnabled })
        }

        @Test func indexingStepShowsProgressBeforeFilesAppear() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.daemon.onStatus = { _ in Wire.status(entries: 0) }
            await env.app.daemon.refresh()
            let flow = OnboardingFlow(app: env.app, defaults: env.defaults, step: .indexing)
            flow.apply()
            #expect(!flow.facts.indexReady)
            let w = await render(OnboardingView(flow: flow).environmentObject(env.app), size: NSSize(width: 440, height: 300))
            defer { w.close() }
            #expect(await axWait("Indexing your disk", in: w) != nil)
        }
    }
}
