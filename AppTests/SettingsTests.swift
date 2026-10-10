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

        func make(_ env: TestEnv, helper: FakeHelper?, login: FakeLoginItem?, exists: @escaping (URL) -> Bool = { _ in true },
                  cliAgent: Bool = false, shortcutResets: Box = Box()) -> Uninstaller {
            Uninstaller(helper: helper, loginItem: login, workspace: env.workspace, defaults: env.defaults,
                        dataFolder: data, logFolder: logs, exists: exists, cliAgentInstalled: { cliAgent },
                        resetShortcut: { shortcutResets.n += 1 })
        }

        final class Box { var n = 0 }

        func seed(_ env: TestEnv) {
            for k in Uninstaller.defaultsKeys { env.defaults.set("x", forKey: k) }
            env.defaults.set("keep", forKey: "other")
        }

        @Test func ownedHelperRemovesEverything() async {
            let env = TestEnv()
            defer { env.tearDown() }
            seed(env)
            let helper = FakeHelper(.enabled), login = FakeLoginItem(.enabled), box = Box()
            let u = make(env, helper: helper, login: login, shortcutResets: box)
            await u.run(ownsDaemon: true)
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
            await u.run(ownsDaemon: false)
            #expect(helper.unregistered == 0 && login.unregistered == 0)
            #expect(env.workspace.trashed == [logs])
            guard case let .done(r) = u.phase else { Issue.record("not done"); return }
            #expect(r.kept.count == 1 && r.kept[0].contains("wasn't enabled"))
            #expect(!r.kept[0].contains("command-line"))
        }

        @Test func helperAwaitingApprovalIsUnregisteredButDataKept() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let helper = FakeHelper(.requiresApproval)
            let u = make(env, helper: helper, login: nil)
            await u.run(ownsDaemon: false)
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
            await u.run(ownsDaemon: true)
            #expect(helper.unregistered == 1)
            #expect(env.workspace.trashed == [logs])
            guard case let .done(r) = u.phase else { Issue.record("not done"); return }
            #expect(r.kept.count == 1 && r.kept[0].contains("mt.nd.fsearch"))
        }

        @Test func sparkleDefaultsAreRemovedToo() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let sparkle = ["SUEnableAutomaticChecks", "SUHasLaunchedBefore", "SULastCheckTime", "SUSendProfileInfo"]
            for k in sparkle { env.defaults.set(true, forKey: k) }
            await make(env, helper: nil, login: nil).run(ownsDaemon: false)
            for k in sparkle { #expect(env.defaults.object(forKey: k) == nil, "\(k)") }
        }

        @Test func helperFailureKeepsTheDataFolder() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let helper = FailingHelper()
            let u = Uninstaller(helper: helper, loginItem: nil, workspace: env.workspace, defaults: env.defaults,
                                dataFolder: data, logFolder: logs, exists: { _ in true }, cliAgentInstalled: { false },
                                resetShortcut: {})
            await u.run(ownsDaemon: true)
            #expect(!env.workspace.trashed.contains(data))
            guard case let .done(r) = u.phase else { Issue.record("not done"); return }
            #expect(r.failures.count == 1 && r.kept.count == 1)
        }

        @Test func trashFailureAndMissingFolders() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.workspace.trashError = TestError("locked")
            let u = make(env, helper: FakeHelper(.enabled), login: nil)
            await u.run(ownsDaemon: true)
            guard case let .done(r) = u.phase else { Issue.record("not done"); return }
            #expect(r.failures.count == 2)

            let u2 = make(env, helper: nil, login: nil, exists: { _ in false })
            env.workspace.trashError = nil
            await u2.run(ownsDaemon: true)
            #expect(env.workspace.trashed.isEmpty)
        }

        @Test func opensFullDiskAccess() {
            let env = TestEnv()
            defer { env.tearDown() }
            make(env, helper: nil, login: nil).openFullDiskAccess()
            #expect(env.workspace.opened == [Uninstaller.fullDiskAccessURL])
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
