import AppKit
import FSearchKit
import Foundation
import Observation
import Sparkle
import SwiftUI
import Testing

@testable import FSearch

extension AppTests {
    @Suite @MainActor
    struct DebugModeTests {
        @Test func turningOffClearsTheLog() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let app = env.app
            DebugMode.set(true, app: app, dismiss: nil)
            #expect(app.debugMode)
            app.search.query = "q"
            await app.search.refresh()
            app.log.flush()
            #expect(FileManager.default.fileExists(atPath: app.log.file.path))
            DebugMode.set(false, app: app, dismiss: nil)
            #expect(!app.debugMode)
            #expect(!FileManager.default.fileExists(atPath: app.log.file.path))
        }

        /// Turning it off closes both debug windows; turning it on closes none.
        @Test func turningOffDismissesTheDebugWindows() {
            let env = TestEnv()
            defer { env.tearDown() }
            var dismissed: [String] = []
            DebugMode.set(true, app: env.app, dismissWindow: { dismissed.append($0) })
            #expect(dismissed.isEmpty)
            DebugMode.set(false, app: env.app, dismissWindow: { dismissed.append($0) })
            #expect(dismissed == ["index", "log"])
        }
    }

    @Suite @MainActor
    struct MenuBarStatusTests {
        @Test func iconFollowsTheDaemon() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let status = MenuBarStatus(defaults: env.defaults)
            #expect(status.icon(for: env.app) == "magnifyingglass")
            #expect(status.icon(for: env.app) == "magnifyingglass")  // binds once
            env.daemon.onStatus = { _ in throw DaemonError.disconnected }
            await env.app.daemon.refresh()
            #expect(await eventually { status.warning?.offersFix == true })
            #expect(status.icon(for: env.app) == "exclamationmark.magnifyingglass")

            // From failed straight to indexing: the warning goes.
            env.daemon.onStatus = { _ in throw DaemonError.indexing("indexing") }
            await env.app.daemon.refresh()
            #expect(await eventually { status.warning == nil })
            #expect(status.icon(for: env.app) == "magnifyingglass")

            // Its flags come from the injected defaults, not .standard.
            env.defaults.set(true, forKey: "skippedFullDiskAccess")
            env.daemon.onStatus = { _ in Wire.status(fullDiskAccess: false) }
            await env.app.daemon.refresh()
            #expect(await eventually { status.warning?.offersFullDiskAccess == true })
        }

        /// Defaults can change on any thread (the crash this guards against):
        /// an off-main didChange post must not trap, and the warning follows it.
        @Test func defaultsChangedOffMainUpdatesTheWarning() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let status = MenuBarStatus(defaults: env.defaults)
            env.daemon.onStatus = { _ in Wire.status(fullDiskAccess: false) }
            _ = status.icon(for: env.app)
            await env.app.daemon.refresh()
            #expect(await eventually { env.app.daemon.state == .running(Wire.status(fullDiskAccess: false)) })
            // Not skipped: revoked FDA keeps the exclamation icon, offers the action button, and cannot be dismissed.
            #expect(await eventually { status.warning != nil })
            #expect(status.warning?.offersFullDiskAccess == true)
            #expect(status.warning?.symbol == "exclamationmark.magnifyingglass")
            let suite = env.suite
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async {
                    let defaults = UserDefaults(suiteName: suite)!
                    defaults.set(true, forKey: "skippedFullDiskAccess")
                    NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
                    done.resume()
                }
            }
            #expect(await eventually { status.warning?.symbol == "magnifyingglass.circle" })
        }

        @Test func approvalWarning() async {
            let env = TestEnv(helper: FakeHelper(.requiresApproval))
            defer { env.tearDown() }
            let status = MenuBarStatus(defaults: env.defaults)
            _ = status.icon(for: env.app)
            env.daemon.onPing = { _ in false }
            await env.app.daemon.start()
            #expect(await eventually { status.warning?.message == "The background helper needs your approval" })
        }

        @Test func restartBudgetDefaults() {
            var b = MenuBarStatus().restartBudget
            let spent = [b.spend(), b.spend(), b.spend(), b.spend()]
            #expect(spent == [true, true, true, false])
            b.reset()
            let again = b.spend()
            #expect(again)
        }
    }

    @Suite @MainActor
    struct FullDiskAccessReminderTests {
        @Test func opensTheFullDiskAccessPane() {
            let env = TestEnv()
            defer { env.tearDown() }
            FullDiskAccessReminder.openSettings()
            #expect(
                env.workspace.opened.map(\.absoluteString)
                    == ["x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"])
        }

        @Test func dontRemindMeStoresTheFlagThatHidesTheReminder() {
            let name = TestEnv.unitSuite
            let defaults = TestEnv.emptySuite(name)
            defer { _ = TestEnv.emptySuite(name) }
            #expect(!defaults.bool(forKey: "dismissedFullDiskAccessReminder"))
            let off = DaemonCondition.running(fullDiskAccess: false)
            #expect(
                MenuBarWarning.evaluate(
                    off, skippedFullDiskAccess: true,
                    dismissedReminder: defaults.bool(forKey: FullDiskAccessReminder.dismissedKey)) != nil)
            FullDiskAccessReminder.dismiss(defaults: defaults)
            #expect(defaults.bool(forKey: "dismissedFullDiskAccessReminder"))
            #expect(
                MenuBarWarning.evaluate(
                    off, skippedFullDiskAccess: true,
                    dismissedReminder: defaults.bool(forKey: FullDiskAccessReminder.dismissedKey)) == nil)
        }
    }

    @Suite @MainActor
    struct UpdaterTests {
        @Test func placeholderKeyNeverStartsSparkle() async {
            #expect(!Updater.isConfigured)
            Updater.start()
            #expect(Updater.controller == nil)
            let w = await render(CheckForUpdatesItem(), size: NSSize(width: 200, height: 40))
            w.close()
        }

        @Test func controllerIsObservableWhenInstalledLater() async {
            defer { Updater.setController(nil) }
            let changed = AsyncGate()
            withObservationTracking {
                _ = Updater.controller
            } onChange: {
                changed.release()
            }
            let c = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
            Updater.setController(c)
            await changed.wait()
            #expect(Updater.controller === c)
            let state = AutoCheckState(updater: c.updater)
            #expect(state.canCheck == c.updater.canCheckForUpdates)
        }
    }

    @Suite @MainActor
    struct ViewTests {
        @Test func iconCache() {
            let c = IconCache()
            #expect(c.typeCountLimit > 0 && c.pathCountLimit > 0)
            let a = c.icon(for: "/p/a.swift")
            #expect(c.icon(for: "/p/b.swift") === a)  // cached by type
            let app1 = c.icon(for: "/Applications/Safari.app")
            #expect(app1.size.width > 0)
            #expect(c.icon(for: "/Applications/Safari.app") === app1)  // cached by path
            let dir1 = c.icon(for: NSTemporaryDirectory(), isDirectory: true)
            #expect(dir1.size.width > 0)
            #expect(c.icon(for: NSTemporaryDirectory(), isDirectory: true) === dir1)  // cached by path
        }

        @Test func resultRowShowsNoBidiControlsInNameFolderOrLabels() {
            let item = ResultItem.file(Wire.hit("/p\u{202E}q/invoice\u{202E}fdp.exe"))
            #expect(String(ResultRow.nameText(for: item, query: "").characters) == "invoice\u{FFFD}fdp.exe")
            #expect(String(ResultRow.detailText(for: item, query: "").characters) == "/p\u{FFFD}q")
            #expect(ResultRow.displayName(for: item) == "invoice\u{FFFD}fdp.exe")
            #expect(ResultRow.displayDetail(for: item) == "/p\u{FFFD}q")
            // The path actions use is untouched.
            #expect(item.path == "/p\u{202E}q/invoice\u{202E}fdp.exe")
        }

        @Test func resultRowHighlightsFilenameOrMatchLine() {
            func hasHighlight(_ s: AttributedString) -> Bool {
                s.runs.contains { $0.backgroundColor != nil }
            }
            let fileItem = ResultItem.file(Wire.hit("/p/heron.txt"))
            #expect(hasHighlight(ResultRow.nameText(for: fileItem, query: "HER")))
            #expect(!hasHighlight(ResultRow.detailText(for: fileItem, query: "p")))

            // Content hits highlight the matching line text (not the filename or line number).
            let lineItem = ResultItem.line(path: "/p/heron.swift", match: Match(line: 42, text: "  let needle = 42"))
            #expect(!hasHighlight(ResultRow.nameText(for: lineItem, query: "heron")))
            let detail = ResultRow.detailText(for: lineItem, query: "NEEDLE")
            #expect(hasHighlight(detail))
            // Query matching the line number prefix highlights only inside the match text, not the prefix.
            let numDetail = ResultRow.detailText(for: lineItem, query: "42")
            let highlightedRuns = numDetail.runs.filter { $0.backgroundColor != nil }.map { String(numDetail[$0.range].characters) }
            #expect(highlightedRuns == ["42"])
            let firstRun = numDetail.runs.first.map { String(numDetail[$0.range].characters) }
            #expect(firstRun?.hasPrefix("42 · ") == true)
            #expect(numDetail.runs.first?.backgroundColor == nil)
        }

        /// Render smoke test (coverage only): SwiftUI's text isn't readable in-process.
        @Test func resultRowsRenderSmoke() async {
            let w = await render(
                VStack {
                    ResultRow(item: .file(Wire.hit("/p/heron.txt")), query: "her", selected: true)
                    ResultRow(
                        item: .line(path: "/p/main.swift", match: Match(line: 3, text: "  func main()")), query: "main x", selected: false)
                    ResultRow(item: .file(Wire.hit("/p/x.txt")), query: "", selected: false)
                })
            w.close()
        }

        /// Render smoke test (coverage only). The debug-only items are checked
        /// end to end by AppUITests.testMenuBarItemListsTheMenu.
        @Test func menuContentRenderSmoke() async {
            for debug in [false, true] {
                let env = TestEnv()
                defer { env.tearDown() }
                env.app.debugMode = debug
                let status = MenuBarStatus(defaults: env.defaults)
                let w = await render(
                    VStack {
                        MenuBarFixItem(app: env.app, status: status)
                        MenuContent(app: env.app)
                        MenuBarLabel(app: env.app, status: status)
                    })
                w.close()
            }
        }

        /// Render smoke test (coverage only); the Settings window is checked by AppUITests.
        @Test func settingsRenderSmoke() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.workspace.apps = Dictionary(
                uniqueKeysWithValues: Editor.allCases.map { ($0.bundleId, URL(fileURLWithPath: "/Applications/\($0.rawValue).app")) })
            let w = await render(SettingsView().environmentObject(env.app), size: NSSize(width: 440, height: 200))
            w.close()
        }

        @Test func indexDetailsInEveryState() async {
            let env = TestEnv(helper: FakeHelper(.requiresApproval))
            defer { env.tearDown() }
            let dataDir = DebugFormat.dataDir(socketPath: env.app.options.socketPath)
            try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
            try? "/Users/x/Library/Mail\n".write(to: dataDir.appendingPathComponent("skipped"), atomically: true, encoding: .utf8)
            try? "started\nindexed 42\n".write(to: dataDir.appendingPathComponent("daemon.log"), atomically: true, encoding: .utf8)
            let w = await render(
                IndexDetailsView().environmentObject(env.app), size: NSSize(width: 520, height: 600), settle: .milliseconds(300))
            #expect(env.app.daemon.state == .running(Wire.status()))
            // The view polls every second: each daemon state is picked up.
            env.daemon.onStatus = { _ in throw DaemonError.indexing("indexing") }
            #expect(await eventually { env.app.daemon.state == .indexing })
            env.daemon.onStatus = { _ in throw DaemonError.disconnected }
            #expect(await eventually { env.app.daemon.state == .needsApproval })
            w.close()
            for s in [DaemonManager.State.checking, .failed("down")] {
                let e = TestEnv()
                defer { e.tearDown() }
                if case .failed = s {
                    e.daemon.onStatus = { _ in throw DaemonError.disconnected }
                    await e.app.daemon.refresh()
                }
                e.daemon.onStatus = { _ in throw CancellationError() }  // stays as it is
                let w2 = await render(IndexDetailsView().environmentObject(e.app), size: NSSize(width: 520, height: 600))
                defer { w2.close() }
                if s == .checking {
                    #expect(e.app.daemon.state == .checking)
                } else {
                    #expect(e.app.daemon.state == .failed("The background helper isn't answering."))
                }
            }
        }

        /// Render smoke test plus the filter the view applies (the table's text
        /// isn't readable in-process).
        @Test func searchLogRenderSmokeAndFilter() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.app.debugMode = true
            for q in ["alpha", "beta"] {
                env.app.search.query = q
                await env.app.search.refresh()
            }
            let w = await render(
                SearchLogView().environmentObject(env.app), size: NSSize(width: 760, height: 420), settle: .milliseconds(400))
            defer { w.close() }
            #expect(env.app.log.entries().count == 2)
            // What the view filters (on a copy, off the main actor), as it does it.
            let rows = env.app.log.entries()
            #expect(DebugFormat.shown(rows, filter: "alp").map(\.query) == ["alpha"])
            #expect(DebugFormat.shown(rows, filter: "").count == 2)
        }
    }
}
