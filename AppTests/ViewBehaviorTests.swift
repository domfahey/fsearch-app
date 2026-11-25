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

            try #require(axNode("Don't Remind Me", in: w)).press()
            #expect(env.defaults.bool(forKey: FullDiskAccessReminder.dismissedKey))
        }

        /// Revoked Full Disk Access (never skipped): offers the action button, but not "Don't Remind Me".
        @Test func revokedFullDiskAccessOffersActionWithoutDismiss() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            env.daemon.onStatus = { _ in Wire.status(fullDiskAccess: false) }
            let s = await status(env) { $0.warning?.offersFullDiskAccess == true }
            let w = await render(VStack { MenuBarFixItem(app: env.app, status: s) })
            defer { w.close() }
            let grant = try #require(await axWait(MenuBarWarning.fullDiskAccessItemTitle(ownsDaemon: false), in: w))
            #expect(!axTexts(in: w).contains("Don't Remind Me"))
            grant.press()
            #expect(env.workspace.opened == [FullDiskAccessReminder.settingsURL])
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
            env.app.log.flush()
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

        /// Debug window, Settings, About, and Quit items in MenuContent route through their seams.
        @Test func menuContentActionsRouteThroughSeams() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            env.app.debugMode = true
            let savedActivate = AppActivation.activate
            let savedAbout = AppMenuActions.showAbout
            let savedQuit = AppMenuActions.quit
            var events: [String] = []
            AppActivation.activate = { events.append("activate") }
            AppMenuActions.showAbout = { events.append("about") }
            AppMenuActions.quit = { events.append("quit") }
            defer {
                AppActivation.activate = savedActivate
                AppMenuActions.showAbout = savedAbout
                AppMenuActions.quit = savedQuit
            }
            let view = VStack {
                MenuContent(
                    app: env.app,
                    openWindow: { events.append("window:\($0)") },
                    openSettings: { events.append("settings") })
            }
            let w = await render(view, size: NSSize(width: 300, height: 420))
            defer { w.close() }
            try #require(await axWait("Index Details…", in: w)).press()
            try #require(axNode("Search Log…", in: w)).press()
            try #require(axNode("Settings…", in: w)).press()
            try #require(axNode("About FSearch", in: w)).press()
            try #require(axNode("Quit FSearch", in: w)).press()
            #expect(
                events == [
                    "activate", "window:index", "activate", "window:log", "activate", "settings", "about", "quit",
                ])

            // Help submenu items open documentation, community links, and the prefilled issue form.
            let helpWindow = await render(VStack { HelpMenuContent(app: env.app) }, size: NSSize(width: 300, height: 320))
            defer { helpWindow.close() }
            try #require(await axWait(HelpLinks.items[0].title, in: helpWindow)).press()
            try #require(axNode(HelpLinks.community[0].title, in: helpWindow)).press()
            try #require(axNode(HelpLinks.reportTitle, in: helpWindow)).press()
            #expect(env.workspace.opened.count == 3)
            #expect(env.workspace.opened[0] == HelpLinks.items[0].url)
            #expect(env.workspace.opened[1] == HelpLinks.community[0].url)
            #expect(env.workspace.opened[2].absoluteString.hasPrefix(IssueReport.newIssueBase))
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

        @Test func uninstalledSavedEditorIsStillShownInSettings() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.app.editor = .bbedit
            let w = await show(env, login: LoginItemModel(service: nil), uninstaller: uninstaller(env))
            defer { w.close() }
            #expect(await axWait("BBEdit (not installed)", in: w) != nil)
        }

        @Test func hotkeyConflictWarningShowsInSettings() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let view = SettingsView(
                loginItem: LoginItemModel(service: nil), uninstaller: uninstaller(env),
                runningBundleIds: { ["com.raycast.macos"] }
            ).environmentObject(env.app)
            let w = await render(view, size: NSSize(width: 440, height: 600))
            defer { w.close() }
            #expect(await eventually { axTexts(in: w).contains { $0.contains("Raycast") } })
        }

        /// Becoming active refreshes the login item status in Settings.
        @Test func becomingActiveRefreshesLoginItem() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let item = FakeLoginItem(.requiresApproval)
            let login = LoginItemModel(service: item)
            let w = await show(env, login: login, uninstaller: uninstaller(env))
            defer { w.close() }
            #expect(await axWait("Open Login Items…", in: w) != nil)
            item.status = .enabled
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
            #expect(await eventually { login.display == .on && !axTexts(in: w).contains("Open Login Items…") })
        }

        /// Running removal shows progress; finishing with kept/failure items displays them and refreshes login status.
        @Test func removalProgressAndKeptFailureReportShowInSettings() async {
            let gate = AsyncGate()
            let helper = FakeHelper(.enabled)
            helper.onUnregister = { await gate.wait() }
            let env = TestEnv(helper: helper)
            defer { env.tearDown() }
            env.workspace.trashError = TestError("disk locked")
            let item = FakeLoginItem(.enabled)
            let login = LoginItemModel(service: item)
            let u = Uninstaller(
                helper: helper, loginItem: item, workspace: env.workspace, defaults: env.defaults,
                dataFolder: data, logFolder: logs, exists: { _ in true }, cliAgentInstalled: { false }, resetShortcut: {})
            let w = await show(env, login: login, uninstaller: u)
            defer { w.close() }

            let task = Task { await SettingsView.performRemoval(app: env.app, uninstaller: u, loginItem: login) }
            #expect(await axWait("Removing…", in: w) != nil)
            gate.release()
            await task.value
            #expect(login.display == .off)
            #expect(await axWait("Done", in: w) != nil)
            let texts = axTexts(in: w)
            #expect(texts.contains { $0.contains("was left alone") })
            #expect(texts.contains { $0.contains("disk locked") })
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

        /// Export configures the save panel, writes JSONL on OK, ignores Cancel, and surfaces write errors inline.
        @Test func exportWritesJsonlHandlesCancelAndShowsErrors() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            env.app.debugMode = true
            for q in ["alpha", "beta"] {
                env.app.search.query = q
                await env.app.search.refresh()
            }
            let goodURL = env.dir.appendingPathComponent("exported.jsonl")
            let badURL = env.dir.appendingPathComponent("missing-dir/exported.jsonl")
            var targets: [URL?] = [nil, goodURL, badURL]
            var suggestedNames: [String] = []
            let view = SearchLogView(filter: "alp") { panel in
                suggestedNames.append(panel.nameFieldStringValue)
                return targets.isEmpty ? nil : targets.removeFirst()
            }.environmentObject(env.app)
            let w = await render(view, size: NSSize(width: 760, height: 420), settle: .milliseconds(300))
            defer { w.close() }

            let exportButton = try #require(await axWait("Export…", in: w))
            // 1. Cancelled save panel: writes nothing, shows no error.
            exportButton.press()
            #expect(!FileManager.default.fileExists(atPath: goodURL.path))
            #expect(!axTexts(in: w).contains { $0.contains("Export failed:") })

            // 2. Valid path: writes all rows as JSONL.
            exportButton.press()
            let written = try String(contentsOf: goodURL, encoding: .utf8)
            #expect(written.contains("alpha") && written.contains("beta"))

            // 3. Unwritable path: displays the inline export error.
            exportButton.press()
            #expect(await eventually { axTexts(in: w).contains { $0.contains("Export failed:") } })
            #expect(suggestedNames == ["fsearch-searches.jsonl", "fsearch-searches.jsonl", "fsearch-searches.jsonl"])
        }
    }

    @Suite @MainActor
    struct IndexDetailsViewTests {
        /// Pressing every action button in IndexDetailsView reveals data, saves, restarts, copies a report, and opens Login Items.
        @Test func indexDetailsButtonsPerformTheirActions() async throws {
            let helper = FakeHelper(.enabled)
            let env = TestEnv(helper: helper)
            defer { env.tearDown() }
            env.daemon.onPing = { _ in false }
            let dataDir = DebugFormat.dataDir(socketPath: env.app.options.socketPath)
            try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
            try "/Users/x/Library/Mail\n".write(to: dataDir.appendingPathComponent("skipped"), atomically: true, encoding: .utf8)
            try "started\n".write(to: dataDir.appendingPathComponent("daemon.log"), atomically: true, encoding: .utf8)

            let w = await render(
                IndexDetailsView().environmentObject(env.app), size: NSSize(width: 520, height: 600), settle: .milliseconds(200))
            defer { w.close() }
            try #require(await axWait("Reveal Data Folder", in: w)).press()
            #expect(env.workspace.revealed == [[dataDir]])
            try #require(axNode("Save Now", in: w)).press()
            #expect(await eventually { env.daemon.saves == 1 })
            try #require(axNode("Restart Daemon", in: w)).press()
            #expect(await eventually { helper.unregistered == 1 })
            try #require(axNode("Copy All", in: w)).press()
            let copied = env.pasteboard.string(forType: .string) ?? ""
            #expect(copied.contains("state:") && copied.contains("/Users/x/Library/Mail") && copied.contains("started"))

            // Approval state exposes Open Login Items Settings.
            let approvalHelper = FakeHelper(.requiresApproval)
            let env2 = TestEnv(helper: approvalHelper)
            defer { env2.tearDown() }
            env2.daemon.onStatus = { _ in throw DaemonError.disconnected }
            await env2.app.daemon.refresh()
            let w2 = await render(IndexDetailsView().environmentObject(env2.app), size: NSSize(width: 520, height: 600))
            defer { w2.close() }
            try #require(await axWait("Open Login Items Settings", in: w2)).press()
            #expect(approvalHelper.openedSettings == 1)
        }
    }

    @Suite @MainActor
    struct SearchViewTests {
        final class Recorder {
            var effects: [(effect: PanelEffect, paths: [String])] = []
            var commands: [AppCommand] = []
            var selections: [Int] = []
        }

        func view(
            _ env: TestEnv, _ r: Recorder, held: HeldKeyBox = HeldKeyBox(), keys: PanelKeyFeed = PanelKeyFeed(),
            menu: AppMenuState? = nil
        ) -> some View {
            SearchView(
                model: env.app.search, state: PanelState(), held: held, keys: keys, geometry: PanelGeometry(),
                menu: menu ?? AppMenuState(held: held), isVisible: { true },
                onEffect: { e, items in r.effects.append((e, items.map(\.path))) },
                onSelect: { r.selections.append($0) }, onCommand: { r.commands.append($0) }
            ).environmentObject(env.app)
        }

        /// ↵ pressed before the results came: it runs on them once they arrive, opening the top file.
        @Test func aHeldReturnOpensTheTopResultWhenItArrives() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let gate = AsyncGate()
            env.daemon.onSearchAsync = { q in
                await gate.wait()
                return SearchReply(tookUs: 1, hits: [Wire.hit("/p/\(q).txt"), Wire.hit("/p/\(q)2.txt")])
            }
            let r = Recorder(), held = HeldKeyBox()
            let w = await render(view(env, r, held: held))
            defer { w.close() }
            env.app.search.query = "heron"
            #expect(await eventually { env.app.search.phase == .loading })
            #expect(PanelInput.gate(.enter, held: &held.key, model: env.app.search) == nil)
            #expect(held.key.held == .enter)
            gate.release()
            #expect(await eventually { !r.effects.isEmpty })
            #expect(r.effects.first?.effect == .open(0))
            #expect(r.effects.first?.paths == ["/p/heron.txt", "/p/heron2.txt"])
            #expect(held.key.held == nil)
        }

        /// Observes `model` inside its own body so `.onChange` runs in the same SwiftUI transaction as `SearchView`.
        private struct QueryClearingHost<Content: View>: View {
            @Bindable var model: SearchModel
            let trigger: String
            let content: Content

            var body: some View {
                content.onChange(of: PanelInput.answer(model)) { _, new in
                    if new.query == trigger && new.current { model.query = "" }
                }
            }
        }

        /// A held ⌘K waits one turn for layout; if the query clears before that turn runs, it must not open on Recents.
        @Test func aDeferredMenuKeyIsDroppedWhenTheQueryChangesBeforeReplay() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let gate = AsyncGate()
            env.daemon.onSearchAsync = { q in
                await gate.wait()
                return SearchReply(tookUs: 1, hits: [Wire.hit("/p/\(q).txt")])
            }
            env.app.openedRecent(env.file("recent.txt"))
            let r = Recorder(), held = HeldKeyBox()
            let wrapped = QueryClearingHost(model: env.app.search, trigger: "heron", content: view(env, r, held: held))
            let w = await render(wrapped)
            defer { w.close() }
            env.app.search.query = "heron"
            #expect(await eventually { env.app.search.phase == .loading })
            #expect(PanelInput.gate(.cmdK, held: &held.key, model: env.app.search) == nil)
            gate.release()
            #expect(await eventually { env.app.search.query.isEmpty && held.key.held == nil })
            // Let the deferred main-queue block run.
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } }
            try? await Task.sleep(for: .milliseconds(50))
            #expect(r.effects.isEmpty, "deferred ⌘K fired after query cleared: \(r.effects)")
        }

        /// Quick Look ↑/↓ must not move the launcher's selection behind an open FSearch menu.
        @Test func quickLookArrowsAreIgnoredWhileTheAppMenuIsOpen() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.daemon.onSearch = { q in SearchReply(tookUs: 1, hits: [Wire.hit("/p/\(q)1.txt"), Wire.hit("/p/\(q)2.txt")]) }
            let r = Recorder(), keys = PanelKeyFeed(), menu = AppMenuState()
            let w = await render(view(env, r, keys: keys, menu: menu))
            defer { w.close() }
            env.app.search.query = "plover"
            #expect(await eventually { env.app.search.phase == .results })
            menu.toggle()
            keys.send(.down)
            try? await Task.sleep(for: .milliseconds(80))
            #expect(r.selections.last != 1, "selection moved while FSearch menu was open")

            menu.close()
            keys.send(.down)
            #expect(await eventually { r.selections.last == 1 })
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
            let id = "command-\(AppCommand.settings.id)"
            try #require(await axWait(id: id, in: w)).press()
            #expect(r.commands == [.settings])
        }

        @Test func footerHintsMatchSelectedRowAndEditor() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let r = Recorder()
            let w = await render(view(env, r))
            defer { w.close() }
            // Command row selected: no file-only hints ("Reveal in Finder", "Actions").
            env.app.search.query = "settings"
            #expect(await axWait(id: "command-\(AppCommand.settings.id)", in: w) != nil)
            let cmdTexts = axTexts(in: w)
            #expect(!cmdTexts.contains("Reveal in Finder"))
            #expect(!cmdTexts.contains("Actions"))

            // Content row with default app (no line-jumping editor): says "Open", not "Open at line".
            env.daemon.onGrep = { _, _, _ in Wire.grep([("/p/main.swift", [(7, "let needle = 1")])]) }
            env.app.search.mode = .content
            env.app.search.query = "needle"
            #expect(await axWait("main.swift", in: w) != nil)
            let contentTexts = axTexts(in: w)
            #expect(!contentTexts.contains("Open at line"))
            #expect(contentTexts.contains("Open"))
            #expect(contentTexts.contains("Actions"))
        }

        @Test func resultRowExposesAccessibilitySelectionAndLabel() async throws {
            let item = ResultItem.file(Wire.hit("/p/heron.txt"))
            var activated = 0
            let w = await render(
                VStack {
                    ResultRow(item: item, query: "her", selected: true) { activated += 1 }
                    ResultRow(item: .file(Wire.hit("/p/other.txt")), query: "her", selected: false)
                })
            defer { w.close() }
            let row = try #require(await axWait(id: "result-/p/heron.txt", in: w))
            #expect(row.isSelected || row.value == "selected")
            #expect(row.label.contains("heron.txt"))
            row.press()
            #expect(activated == 1)
            let other = try #require(axNode(id: "result-/p/other.txt", in: w))
            #expect(!other.isSelected && other.value == "")
        }
    }
}
