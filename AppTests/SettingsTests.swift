import FSearchKit
import Foundation
import Testing

@testable import FSearch

extension AppTests {
    @Suite @MainActor
    struct LoginItemModelTests {
        @Test func reflectsTheRealStatus() {
            #expect(LoginItemModel(service: FakeLoginItem(.enabled)).display == .on)
            #expect(LoginItemModel(service: FakeLoginItem(.notRegistered)).display == .off)
            #expect(LoginItemModel(service: FakeLoginItem(.notFound)).display == .off)
            let m = LoginItemModel(service: FakeLoginItem(.requiresApproval))
            #expect(m.display == .needsApproval)
            #expect(m.isOn)
            #expect(LoginItemModel(service: nil).display == .unavailable)
        }

        @Test func turningOnAndOff() async {
            let item = FakeLoginItem(.notRegistered)
            let m = LoginItemModel(service: item)
            await m.set(true)
            #expect(item.registered == 1 && m.display == .on && m.error == nil)
            await m.set(false)
            #expect(item.unregistered == 1 && m.display == .off)
        }

        @Test func failureIsInlineAndStatusStaysReal() async {
            let item = FakeLoginItem(.notRegistered)
            item.registerError = TestError("denied")
            let m = LoginItemModel(service: item)
            await m.set(true)
            #expect(m.display == .off)
            #expect(m.error?.contains("denied") == true)
            item.registerError = nil
            await m.set(true)
            #expect(m.error == nil)
            item.unregisterError = TestError("locked")
            await m.set(false)
            #expect(m.display == .on && m.error?.contains("locked") == true)
        }

        @Test func overlappingToggleCallsAreIgnored() async {
            let gate = AsyncGate()
            let item = SlowLoginItem(gate: gate)
            let m = LoginItemModel(service: item)
            let first = Task { await m.set(false) }
            await Task.yield()
            await m.set(true)
            gate.release()
            await first.value
            #expect(item.unregistered == 1 && item.registered == 0 && m.display == .off)
        }

        @Test func approvalIsNotAnError() async {
            let item = FakeLoginItem(.notRegistered)
            item.statusAfterRegister = .requiresApproval
            let m = LoginItemModel(service: item)
            await m.set(true)
            #expect(m.display == .needsApproval && m.error == nil)
            m.openLoginItems()
            #expect(item.openedSettings == 1)
        }
    }

    @Suite @MainActor
    struct UninstallerTests {
        let data = URL(fileURLWithPath: "/fake/Application Support/FSearch")
        let logs = URL(fileURLWithPath: "/fake/Logs/FSearch")

        func make(
            _ env: TestEnv, helper: FakeHelper?, login: FakeLoginItem?, exists: @escaping (URL) -> Bool = { _ in true },
            cliAgent: Bool = false, shortcutResets: Box = Box()
        ) -> Uninstaller {
            Uninstaller(
                helper: helper, loginItem: login, workspace: env.workspace, defaults: env.defaults,
                dataFolder: data, logFolder: logs, exists: exists, cliAgentInstalled: { cliAgent },
                resetShortcut: { shortcutResets.n += 1 })
        }

        final class Box { var n = 0 }

        func seed(_ env: TestEnv) {
            for k in Uninstaller.defaultsKeys { env.defaults.set("x", forKey: k) }
            env.defaults.set("keep", forKey: "other")
        }

        @Test func removalSuspensionSurvivesRelaunchUntilExplicitSetup() async {
            let helper = FakeHelper(.enabled)
            let env = TestEnv(helper: helper)
            defer { env.tearDown() }
            env.daemon.onPing = { _ in false }
            let u = make(env, helper: helper, login: nil)
            await u.run(ownership: .ours, daemon: env.app.daemon)
            #expect(!Uninstaller.defaultsKeys.contains(DaemonManager.recoverySuspendedKey))
            #expect(env.defaults.bool(forKey: DaemonManager.recoverySuspendedKey))

            let reopened = AppState(
                options: env.app.options, defaults: env.defaults, helper: helper,
                names: env.daemon, content: env.daemon, control: env.daemon, clock: env.clock.clock,
                cliAgentInstalled: { false })
            #expect(reopened.daemon.recoverySuspended)
            // A disconnected search restarts; closing onboarding calls start() without resuming.
            await reopened.daemon.restart()
            await OnboardingLauncher.startDaemon(app: reopened).value
            #expect(helper.registered == 0)
            #expect(helper.status == .notRegistered)

            await reopened.daemon.start(resumingAfterRemoval: true)
            #expect(helper.registered == 1)
            #expect(helper.status == .enabled)
            #expect(!reopened.daemon.recoverySuspended)
            #expect(!env.defaults.bool(forKey: DaemonManager.recoverySuspendedKey))
        }

        @Test func removalPreventsDisconnectedSearchFromReinstallingTheHelper() async {
            let helper = FakeHelper(.enabled)
            let env = TestEnv(helper: helper)
            defer { env.tearDown() }
            env.daemon.onPing = { _ in false }
            let u = make(env, helper: helper, login: nil)
            await u.run(ownership: .ours, daemon: env.app.daemon)
            env.app.searchSettled(.failed(.disconnected))
            // Drain any recovery already scheduled by the search observer.
            await env.app.daemon.restart()
            await env.app.daemon.start()
            #expect(helper.registered == 0)
            #expect(helper.status == .notRegistered)
            #expect(env.workspace.trashed.contains(data))
            // The user's explicit setup step can install the helper again.
            await env.app.daemon.start(resumingAfterRemoval: true)
            #expect(helper.registered == 1)
            #expect(helper.status == .enabled)
        }

        @Test func removalWaitsForAnInFlightRestartBeforeTrashingData() async {
            let helper = FakeHelper(.enabled)
            let env = TestEnv(helper: helper)
            defer { env.tearDown() }
            env.daemon.onPing = { _ in false }
            var release: CheckedContinuation<Void, Never>?
            helper.onUnregister = {
                if helper.unregistered == 1 {
                    await withCheckedContinuation { release = $0 }
                }
            }
            let restart = Task { await env.app.daemon.restart() }
            #expect(await eventually { release != nil })
            let u = make(env, helper: helper, login: nil)
            let removal = Task { await u.run(ownership: .ours, daemon: env.app.daemon) }
            #expect(await eventually { u.phase != .idle })
            // A suspended unregister cannot be cancelled out of SMAppService; removal must await it.
            for _ in 0..<20 { await Task.yield() }
            #expect(env.workspace.trashed.isEmpty)
            await env.app.daemon.start(resumingAfterRemoval: true)
            #expect(helper.registered == 0, "setup must wait until removal finishes")
            release?.resume()
            await restart.value
            await removal.value
            #expect(helper.registered == 0)
            #expect(env.workspace.trashed.contains(data))
        }

        @Test func ownedHelperRemovesEverything() async {
            let env = TestEnv()
            defer { env.tearDown() }
            seed(env)
            let helper = FakeHelper(.enabled), login = FakeLoginItem(.enabled), box = Box()
            let u = make(env, helper: helper, login: login, shortcutResets: box)
            await u.run(ownership: .ours)
            #expect(helper.unregistered == 1 && login.unregistered == 1)
            #expect(env.workspace.trashed == [data, logs])
            for k in Uninstaller.defaultsKeys { #expect(env.defaults.object(forKey: k) == nil) }
            #expect(env.defaults.string(forKey: "other") == "keep")
            #expect(box.n == 1)
            guard case let .done(r) = u.phase else { Issue.record("not done"); return }
            #expect(r.failures.isEmpty && r.kept.isEmpty)
            #expect(r.removed.count == 5)
        }

        @Test func cliDaemonIsNeverTouched() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let helper = FakeHelper(.notRegistered), login = FakeLoginItem(.notRegistered)
            let u = make(env, helper: helper, login: login)
            await u.run(ownership: .helperOff)
            #expect(helper.unregistered == 0 && login.unregistered == 0)
            #expect(env.workspace.trashed == [logs])
            guard case let .done(r) = u.phase else { Issue.record("not done"); return }
            #expect(r.kept.count == 1 && r.kept[0].contains("wasn't enabled"))
            #expect(!r.kept[0].contains("command-line"))
        }

        /// Another daemon on the socket, or none we can name, keeps the data folder, and the report says which.
        @Test func dataIsKeptUnlessOwnershipIsPositive() async {
            let env = TestEnv()
            defer { env.tearDown() }
            for (ownership, reason) in [(DataOwnership.otherDaemon, "another fsearch daemon"), (.unconfirmed, "couldn't confirm")] {
                let helper = FakeHelper(.enabled)
                let u = make(env, helper: helper, login: nil)
                await u.run(ownership: ownership)
                #expect(helper.unregistered == 1)
                #expect(!env.workspace.trashed.contains(data), "\(ownership)")
                guard case let .done(r) = u.phase else { Issue.record("not done"); return }
                #expect(r.kept.count == 1 && r.kept[0].contains(reason) && !r.kept[0].contains("wasn't enabled"), "\(r.kept)")
            }
        }

        @Test func theManagerReportsOwnershipFromTheHolder() {
            let env = TestEnv(helper: FakeHelper(.enabled))
            defer { env.tearDown() }
            #expect(env.app.daemon.dataOwnership == .unconfirmed, "TestEnv's holder is none")
            let ours = DaemonManager(client: env.daemon, service: FakeHelper(.enabled), socketHolder: { .ours }, defaults: env.defaults)
            #expect(ours.dataOwnership == .ours)
            let testMode = DaemonManager(client: env.daemon, service: nil, socketHolder: { .ours }, defaults: env.defaults)
            #expect(testMode.dataOwnership == .helperOff, "test mode has no helper")
        }

        @Test func helperAwaitingApprovalIsUnregisteredButDataKept() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let helper = FakeHelper(.requiresApproval)
            let u = make(env, helper: helper, login: nil)
            await u.run(ownership: .helperOff)
            #expect(helper.unregistered == 1)
            #expect(!env.workspace.trashed.contains(data))
            guard case let .done(r) = u.phase else { Issue.record("not done"); return }
            #expect(r.removed.contains { $0.contains("background helper") })
            #expect(r.kept.count == 1 && r.kept[0].contains("wasn't enabled"))
        }

        @Test func cliLoginAgentKeepsTheSharedDataFolder() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let helper = FakeHelper(.enabled)
            let u = make(env, helper: helper, login: nil, cliAgent: true)
            await u.run(ownership: .ours)
            #expect(helper.unregistered == 1)
            #expect(env.workspace.trashed == [logs])
            guard case let .done(r) = u.phase else { Issue.record("not done"); return }
            #expect(r.kept.count == 1 && r.kept[0].contains("mt.nd.fsearch"))
        }

        @Test func sparkleDefaultsAreRemovedToo() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let sparkle = [
                "SUEnableAutomaticChecks", "SUHasLaunchedBefore", "SULastCheckTime", "SUSendProfileInfo",
                "SUAutomaticallyUpdate", "SUScheduledCheckInterval", "SUSkippedVersion",
            ]
            for k in sparkle { env.defaults.set(true, forKey: k) }
            await make(env, helper: nil, login: nil).run(ownership: .helperOff)
            for k in sparkle { #expect(env.defaults.object(forKey: k) == nil, "\(k)") }
        }

        @Test func helperFailureKeepsTheDataFolder() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let helper = FailingHelper()
            let u = Uninstaller(
                helper: helper, loginItem: nil, workspace: env.workspace, defaults: env.defaults,
                dataFolder: data, logFolder: logs, exists: { _ in true }, cliAgentInstalled: { false },
                resetShortcut: {})
            await u.run(ownership: .ours)
            #expect(!env.workspace.trashed.contains(data))
            guard case let .done(r) = u.phase else { Issue.record("not done"); return }
            #expect(r.failures.count == 1 && r.kept.count == 1)
        }

        @Test func trashFailureAndMissingFolders() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.workspace.trashError = TestError("locked")
            let u = make(env, helper: FakeHelper(.enabled), login: nil)
            await u.run(ownership: .ours)
            guard case let .done(r) = u.phase else { Issue.record("not done"); return }
            #expect(r.failures.count == 2)

            let u2 = make(env, helper: nil, login: nil, exists: { _ in false })
            env.workspace.trashError = nil
            await u2.run(ownership: .ours)
            #expect(env.workspace.trashed.isEmpty)
            // When the data folder doesn't exist at all, don't report that it was "left alone".
            let u3 = make(env, helper: nil, login: nil, exists: { _ in false })
            await u3.run(ownership: .helperOff)
            guard case let .done(r3) = u3.phase else { Issue.record("not done"); return }
            #expect(r3.kept.isEmpty)
        }

        @Test func opensFullDiskAccess() {
            let env = TestEnv()
            defer { env.tearDown() }
            make(env, helper: nil, login: nil).openFullDiskAccess()
            #expect(env.workspace.opened == [Uninstaller.fullDiskAccessURL])
        }

        @Test func waitsForUnregisteredHelperBeforeTrashingData() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let helper = FakeHelper(.enabled)
            var events: [String] = []
            let u = Uninstaller(
                helper: helper, loginItem: nil, workspace: env.workspace, defaults: env.defaults,
                dataFolder: data, logFolder: logs, exists: { _ in true }, cliAgentInstalled: { false },
                resetShortcut: {},
                waitUntilStopped: {
                    events.append("waited:unreg=\(helper.unregistered):trashed=\(env.workspace.trashed.count)")
                })
            await u.run(ownership: .ours)
            #expect(events == ["waited:unreg=1:trashed=0"])
            #expect(env.workspace.trashed.contains(data))
        }

        @Test func editorOptionsIncludeUninstalledSelectedEditor() {
            let installed: [Editor] = [.vscode]
            #expect(SettingsView.editorOptions(selected: nil, installed: installed).map(\.tag) == ["", "vscode"])
            #expect(SettingsView.editorOptions(selected: .vscode, installed: installed).map(\.tag) == ["", "vscode"])
            let opts = SettingsView.editorOptions(selected: .bbedit, installed: installed)
            #expect(opts.map(\.tag) == ["", "vscode", "bbedit"])
            #expect(opts.last?.label == "BBEdit (not installed)")
        }

        @Test func waitUntilStoppedPollsUntilPingFailsOrCapsAtMaxAttempts() async {
            // Immediate failure -> 0 sleeps.
            var sleeps = 0
            await Uninstaller.waitUntilStopped(ping: { throw DaemonError.disconnected }, sleep: { sleeps += 1 }, maxAttempts: 5)
            #expect(sleeps == 0)

            // Answers twice, fails on 3rd -> 2 sleeps.
            var pings = 0
            await Uninstaller.waitUntilStopped(
                ping: {
                    pings += 1
                    if pings >= 3 { throw DaemonError.disconnected }
                }, sleep: { sleeps += 1 }, maxAttempts: 5)
            #expect(pings == 3 && sleeps == 2)

            // Always answers -> capped at maxAttempts.
            sleeps = 0
            await Uninstaller.waitUntilStopped(ping: {}, sleep: { sleeps += 1 }, maxAttempts: 3)
            #expect(sleeps == 3)
        }

        @Test func reentrantRunIsIgnoredWhileAlreadyRunning() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let gate = AsyncGate()
            let helper = FakeHelper(.enabled)
            helper.onUnregister = { await gate.wait() }
            let u = make(env, helper: helper, login: nil)
            let first = Task { await u.run(ownership: .ours) }
            #expect(await eventually { u.phase == .running })
            await u.run(ownership: .ours)
            gate.release()
            await first.value
            #expect(helper.unregistered == 1)
        }

        @Test func defaultFilesystemChecksHandleMissingTempFolders() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let missingData = env.dir.appendingPathComponent("no-data")
            let missingLog = env.dir.appendingPathComponent("no-log")
            let u = Uninstaller(
                helper: nil, loginItem: nil, workspace: env.workspace, defaults: env.defaults,
                dataFolder: missingData, logFolder: missingLog, resetShortcut: {})
            await u.run(ownership: .ours)
            #expect(env.workspace.trashed.isEmpty)
            // Also verify the default cliAgentInstalled closure runs cleanly when the data folder exists.
            let realData = env.dir.appendingPathComponent("existing-data")
            try? FileManager.default.createDirectory(at: realData, withIntermediateDirectories: true)
            let u2 = Uninstaller(
                helper: nil, loginItem: nil, workspace: env.workspace, defaults: env.defaults,
                dataFolder: realData, logFolder: missingLog, resetShortcut: {})
            await u2.run(ownership: .helperOff)
            #expect(env.workspace.trashed.isEmpty)
        }
    }
}

@MainActor
private final class FailingHelper: HelperService {
    var status: DaemonPlan.ServiceStatus = .enabled
    func register() throws {}
    func unregister() async throws { throw TestError("busy") }
    func openSystemSettingsLoginItems() {}
}

@MainActor
private final class SlowLoginItem: LoginItemService {
    let gate: AsyncGate
    var status: DaemonPlan.ServiceStatus = .enabled
    private(set) var registered = 0, unregistered = 0
    init(gate: AsyncGate) { self.gate = gate }
    func register() throws { registered += 1; status = .enabled }
    func unregister() async throws {
        unregistered += 1
        await gate.wait()
        status = .notRegistered
    }
    func openSystemSettingsLoginItems() {}
}
