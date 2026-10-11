import AppKit
import FSearchKit
import Foundation
import SwiftUI
import Testing

@testable import FSearch

/// Views checked through their accessibility tree (see Support/Accessibility.swift):
/// what they show, and what their buttons do when pressed. Buttons that would
/// open a real window (Settings, About, the debug windows) or quit are never pressed.
extension AppTests {
    /// The tree every test in this file reads: if SwiftUI stops building it in the
    /// test host, this fails with one clear message.
    @Suite @MainActor
    struct AccessibilityTreeTests {
        @Test func theAccessibilityTreeIsBuilt() async throws {
            var presses = 0
            let w = await render(
                VStack {
                    Text("hello"); Button("Press me") { presses += 1 }
                }, size: NSSize(width: 200, height: 80))
            defer { w.close() }
            let button = try #require(
                await axWait("Press me", in: w), "SwiftUI built no accessibility tree in the test host: every view test depends on it")
            #expect(axTexts(in: w).contains("hello"))
            button.press()
            #expect(presses == 1)
        }
    }

    @Suite @MainActor
    struct MenuViewTests {
        /// A status following `env`'s daemon, once the daemon reports `state`.
        func status(_ env: TestEnv, until ready: (MenuBarStatus) -> Bool) async -> MenuBarStatus {
            let s = MenuBarStatus(defaults: env.defaults)
            _ = s.icon(for: env.app)
            await env.app.daemon.refresh()
            #expect(await eventually { ready(s) })
            return s
        }

        @Test func noWarningShowsNoFixItems() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let s = await status(env) { $0.warning == nil && env.app.daemon.state != .checking }
            let w = await render(
                VStack {
                    Text(axSentinel); MenuBarFixItem(app: env.app, status: s)
                })
            defer { w.close() }
            #expect(await axWait(axSentinel, in: w) != nil)
            #expect(axTexts(in: w) == [axSentinel])
        }

        /// A helper that stopped answering: the warning and a Fix… item, no Full Disk Access items.
        @Test func aFailedHelperOffersTheFix() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.daemon.onStatus = { _ in throw DaemonError.disconnected }
            let s = await status(env) { $0.warning?.offersFix == true }
            let w = await render(VStack { MenuBarFixItem(app: env.app, status: s) })
            defer { w.close() }
            #expect(await axWait("Fix…", in: w) != nil)
            let texts = axTexts(in: w)
            #expect(texts.contains(s.warning?.message ?? "-"))
            #expect(texts.contains("Fix…"))
            #expect(!texts.contains("Don't Remind Me"))
        }

        /// Full Disk Access skipped at onboarding: the reminder's items open the
        /// privacy pane and store "don't remind me".
        @Test func theFullDiskAccessReminderItemsAct() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            env.defaults.set(true, forKey: "skippedFullDiskAccess")
            env.daemon.onStatus = { _ in Wire.status(fullDiskAccess: false) }
            let s = await status(env) { $0.warning?.offersFullDiskAccess == true }
            let w = await render(VStack { MenuBarFixItem(app: env.app, status: s) })
            defer { w.close() }
            // Not our helper (test mode), so the CLI binary is the one to grant.
            let grant = try #require(await axWait(MenuBarWarning.fullDiskAccessItemTitle(ownsDaemon: false), in: w))
            #expect(!axTexts(in: w).contains("Fix…"))
            grant.press()
            #expect(env.workspace.opened == [FullDiskAccessReminder.settingsURL])
            #expect(!env.app.daemon.fullDiskAccessRestartArmed, "only our own helper is restarted")

            let store = AppDefaults.store
            defer { store.removeObject(forKey: FullDiskAccessReminder.dismissedKey) }
            try #require(axNode("Don't Remind Me", in: w)).press()
            #expect(store.bool(forKey: FullDiskAccessReminder.dismissedKey))
        }

        /// The debug item says what pressing it does, and turning debug mode off clears the log.
        @Test func theDebugItemTogglesDebugMode() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let w = await render(VStack { DebugMenuItem(app: env.app) })
            defer { w.close() }
            try #require(await axWait("Turn On Debug Mode", in: w)).press()
            #expect(env.app.debugMode)
            env.app.search.query = "q"
            await env.app.search.refresh()
            #expect(FileManager.default.fileExists(atPath: env.app.log.file.path))
            try #require(await axWait("Turn Off Debug Mode", in: w)).press()
            #expect(!env.app.debugMode)
            #expect(!FileManager.default.fileExists(atPath: env.app.log.file.path))
        }

        /// The debug windows are listed only in debug mode; "Search…" shows the launcher.
        @Test func theMenuListsDebugWindowsOnlyInDebugMode() async throws {
            for debug in [false, true] {
                let env = TestEnv()
                defer { env.tearDown() }
                env.app.debugMode = debug
                let w = await render(VStack { MenuContent(app: env.app) }, size: NSSize(width: 300, height: 400))
                defer { w.close() }
                #expect(await axWait("Search…", in: w) != nil)
                let texts = axTexts(in: w)
                #expect(texts.contains("Search…"))
                #expect(texts.contains("Quit FSearch"))
                #expect(texts.contains("Index Details…") == debug)
                #expect(texts.contains("Search Log…") == debug)
                #expect(texts.contains("Turn \(debug ? "Off" : "On") Debug Mode"))
            }
            let env = TestEnv()
            defer { env.tearDown() }
            defer { PanelController.shared.hide(returnFocus: false) }
            let w = await render(VStack { MenuContent(app: env.app) }, size: NSSize(width: 300, height: 400))
            defer { w.close() }
            #expect(!PanelController.shared.isVisible)
            try #require(await axWait("Search…", in: w)).press()
            #expect(PanelController.shared.isVisible)
        }
    }

    @Suite @MainActor
    struct SettingsViewTests {
        let data = URL(fileURLWithPath: "/fake/Application Support/FSearch")
        let logs = URL(fileURLWithPath: "/fake/Logs/FSearch")

        func uninstaller(_ env: TestEnv, helper: FakeHelper? = FakeHelper(.enabled)) -> Uninstaller {
            Uninstaller(
                helper: helper, loginItem: nil, workspace: env.workspace, defaults: env.defaults,
                dataFolder: data, logFolder: logs, exists: { _ in true }, cliAgentInstalled: { false }, resetShortcut: {})
        }

        func show(_ env: TestEnv, login: LoginItemModel, uninstaller u: Uninstaller) async -> NSWindow {
            await render(
                SettingsView(loginItem: login, uninstaller: u).environmentObject(env.app), size: NSSize(width: 440, height: 600))
        }

        /// Awaiting approval: the status says so and a button opens Login Items.
        @Test func awaitingApprovalOffersLoginItems() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let item = FakeLoginItem(.requiresApproval)
            let login = LoginItemModel(service: item)
            let w = await show(env, login: login, uninstaller: uninstaller(env))
            defer { w.close() }
            let open = try #require(await axWait("Open Login Items…", in: w))
            #expect(axTexts(in: w).contains(login.statusText))
            open.press()
            #expect(item.openedSettings == 1)
        }

        /// The toggle registers the login item; a failure shows inline.
        @Test func theLoginToggleRegistersAndShowsErrors() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let item = FakeLoginItem(.notRegistered)
            item.registerError = TestError("denied by policy")
            let login = LoginItemModel(service: item)
            let w = await show(env, login: login, uninstaller: uninstaller(env))
            defer { w.close() }
            let toggle = try #require(await axWait("Open FSearch at login", in: w))
            #expect(!axTexts(in: w).contains("Open Login Items…"))
            toggle.press()
            #expect(await eventually { item.registered == 1 })
            #expect(await eventually { axTexts(in: w).contains { $0.contains("denied by policy") } })
        }

        /// No login-item service (test mode): the toggle is off and disabled.
        @Test func noServiceDisablesTheLoginToggle() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let w = await show(env, login: LoginItemModel(service: nil), uninstaller: uninstaller(env))
            defer { w.close() }
            #expect(try #require(await axWait("Open FSearch at login", in: w)).isEnabled == false)
            // Removing needs the real helper, which test mode never touches.
            #expect(try #require(axNode("Remove Background Helper and Data…", in: w)).isEnabled == false)
        }

        /// After removal the report lists what went; its buttons open the privacy pane and close the report.
        @Test func theRemovalReportShowsAndCloses() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let u = uninstaller(env)
            await u.run(ownership: .ours)
            guard case let .done(report) = u.phase else { Issue.record("not done"); return }
            let w = await show(env, login: LoginItemModel(service: nil), uninstaller: u)
            defer { w.close() }
            #expect(await axWait("Done", in: w) != nil)
            let texts = axTexts(in: w)
            for line in report.removed { #expect(texts.contains(line), "\(line)") }
            #expect(!texts.contains("Remove Background Helper and Data…"))
            try #require(axNode("Open Full Disk Access…", in: w)).press()
            #expect(env.workspace.opened.last == Uninstaller.fullDiskAccessURL)
            try #require(axNode("Done", in: w)).press()
            #expect(u.phase == .idle)
            #expect(await eventually { axNode("Remove Background Helper and Data…", in: w) != nil })
        }

        /// The debug toggle switches debug mode.
        @Test func theDebugToggleSwitchesDebugMode() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let w = await show(env, login: LoginItemModel(service: nil), uninstaller: uninstaller(env))
            defer { w.close() }
            #expect(!env.app.debugMode)
            try #require(await axWait("Debug mode", in: w)).press()
            #expect(await eventually { env.app.debugMode })
        }
    }

    @Suite @MainActor
    struct SearchLogViewTests {
        /// Clear Log deletes the recorded searches; the table's own text isn't exposed in-process, so the log file is checked.
        @Test func clearLogEmptiesTheLog() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            env.app.debugMode = true
            for q in ["alpha", "beta"] {
                env.app.search.query = q
                await env.app.search.refresh()
            }
            let w = await render(SearchLogView().environmentObject(env.app), size: NSSize(width: 760, height: 420))
            defer { w.close() }
            #expect(env.app.log.entries().map(\.query).sorted() == ["alpha", "beta"])
            #expect(await axWait("Export…", in: w) != nil)
            try #require(axNode("Clear Log", in: w)).press()
            #expect(env.app.log.entries().isEmpty)
        }
    }

    @Suite @MainActor
    struct SearchViewTests {
        final class Recorder {
            var effects: [(effect: PanelEffect, paths: [String])] = []
            var commands: [AppCommand] = []
            var selections: [Int] = []
        }

        func view(_ env: TestEnv, _ r: Recorder, held: HeldKeyBox = HeldKeyBox()) -> some View {
            SearchView(
                model: env.app.search, state: PanelState(), held: held, keys: PanelKeyFeed(), geometry: PanelGeometry(),
                menu: AppMenuState(held: held), isVisible: { true },
                onEffect: { e, items in r.effects.append((e, items.map(\.path))) },
                onSelect: { r.selections.append($0) }, onCommand: { r.commands.append($0) }
            ).environmentObject(env.app)
        }

        /// ↵ pressed before the results came: it runs on them once they arrive, opening the top file.
        @Test func aHeldReturnOpensTheTopResultWhenItArrives() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let gate = DispatchSemaphore(value: 0)
            env.daemon.onSearch = { q in
                _ = gate.wait(timeout: .now() + 3)
                return SearchReply(tookUs: 1, hits: [Wire.hit("/p/\(q).txt"), Wire.hit("/p/\(q)2.txt")])
            }
            let r = Recorder(), held = HeldKeyBox()
            let w = await render(view(env, r, held: held))
            defer { w.close() }
            env.app.search.query = "heron"
            #expect(await eventually { env.app.search.phase == .loading })
            #expect(PanelInput.gate(.enter, held: &held.key, model: env.app.search) == nil)
            #expect(held.key.held == .enter)
            gate.signal()
            #expect(await eventually { !r.effects.isEmpty })
            #expect(r.effects.first?.effect == .open(0))
            #expect(r.effects.first?.paths == ["/p/heron.txt", "/p/heron2.txt"])
            #expect(held.key.held == nil)
        }

        /// No files: the fallback rows (pressed as VoiceOver does) re-run the query inside files or as definitions.
        @Test func theFallbackRowsSwitchMode() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let r = Recorder()
            let w = await render(view(env, r))
            defer { w.close() }
            env.app.search.query = "heron"
            #expect(await eventually { env.app.search.phase == .results })
            try #require(await axWait(id: "fallback-content", in: w)).press()
            #expect(env.app.search.mode == .content)
            #expect(await eventually { env.daemon.greps.contains { $0.pattern == "heron" } })
            env.app.search.mode = .names
            try #require(await axWait(id: "fallback-symbols", in: w)).press()
            #expect(env.app.search.mode == .symbols)
        }

        /// "settings" brings up the Settings command row, which runs the command.
        @Test func theCommandRowRunsItsCommand() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let r = Recorder()
            let w = await render(view(env, r))
            defer { w.close() }
            env.app.search.query = "settings"
            let id = "command-\(AppCommand.settings.title)"
            try #require(await axWait(id: id, in: w)).press()
            #expect(r.commands == [.settings])
        }
    }
}
