import AppKit
import FSearchKit
import Foundation
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
            #expect(FileManager.default.fileExists(atPath: app.log.file.path))
            DebugMode.set(false, app: app, dismiss: nil)
            #expect(!app.debugMode)
            #expect(!FileManager.default.fileExists(atPath: app.log.file.path))
            #expect(DebugMode.windowIDs == ["index", "log"])
        }
    }

    @Suite @MainActor
    struct MenuBarStatusTests {
        @Test func iconFollowsTheDaemon() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let status = MenuBarStatus()
            #expect(status.icon(for: env.app) == "magnifyingglass")
            #expect(status.icon(for: env.app) == "magnifyingglass")  // binds once
            env.daemon.onStatus = { _ in throw DaemonError.disconnected }
            await env.app.daemon.refresh()
            #expect(await eventually { status.warning?.offersFix == true })
            #expect(status.icon(for: env.app) == "exclamationmark.magnifyingglass")

            env.daemon.onStatus = { _ in Wire.status(fullDiskAccess: true) }
            await env.app.daemon.refresh()
            #expect(await eventually { status.warning == nil })
            env.daemon.onStatus = { _ in throw DaemonError.indexing("indexing") }
            await env.app.daemon.refresh()
            try? await Task.sleep(for: .milliseconds(30))
            #expect(status.warning == nil)
        }

        @Test func approvalWarning() async {
            let env = TestEnv(helper: FakeHelper(.requiresApproval))
            defer { env.tearDown() }
            let status = MenuBarStatus()
            _ = status.icon(for: env.app)
            env.daemon.onPing = { _ in false }
            await env.app.daemon.start()
            #expect(await eventually { status.warning?.message == "The search helper needs your approval" })
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
            #expect(env.workspace.opened.map(\.absoluteString)
                == ["x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"])
        }

        @Test func dontRemindMeStoresTheFlagThatHidesTheReminder() {
            let name = "fda-reminder-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            #expect(!defaults.bool(forKey: "dismissedFullDiskAccessReminder"))
            let off = DaemonCondition.running(fullDiskAccess: false)
            #expect(MenuBarWarning.evaluate(off, skippedFullDiskAccess: true,
                                            dismissedReminder: defaults.bool(forKey: FullDiskAccessReminder.dismissedKey)) != nil)
            FullDiskAccessReminder.dismiss(defaults: defaults)
            #expect(defaults.bool(forKey: "dismissedFullDiskAccessReminder"))
            #expect(MenuBarWarning.evaluate(off, skippedFullDiskAccess: true,
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
    }

    @Suite @MainActor
    struct ViewTests {
        @Test func iconCache() {
            let c = IconCache()
            let a = c.icon(for: "/p/a.swift")
            #expect(c.icon(for: "/p/b.swift") === a)  // cached by type
            #expect(c.icon(for: "/Applications/Safari.app").size.width > 0)
            #expect(c.icon(for: NSTemporaryDirectory()).size.width > 0)
        }

        @Test func resultRows() async {
            let w = await render(VStack {
                ResultRow(item: .file(Wire.hit("/p/heron.txt")), query: "her", selected: true)
                ResultRow(item: .line(path: "/p/main.swift", match: Match(line: 3, text: "  func main()")), query: "main x", selected: false)
                ResultRow(item: .file(Wire.hit("/p/x.txt")), query: "", selected: false)
            })
            w.close()
        }

        @Test func menuContent() async {
            for debug in [false, true] {
                let env = TestEnv()
                env.app.debugMode = debug
                let w = await render(VStack {
                    MenuBarFixItem(app: env.app)
                    MenuContent(app: env.app)
                    MenuBarLabel(app: env.app)
                })
                w.close()
                env.tearDown()
            }
        }

        @Test func settings() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.workspace.apps = Dictionary(uniqueKeysWithValues: Editor.allCases.map { ($0.bundleId, URL(fileURLWithPath: "/Applications/\($0.rawValue).app")) })
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
            let w = await render(IndexDetailsView().environmentObject(env.app), size: NSSize(width: 520, height: 600), settle: .milliseconds(300))
            #expect(env.app.daemon.state == .running(Wire.status()))
            env.daemon.onStatus = { _ in throw DaemonError.indexing("indexing") }
            try? await Task.sleep(for: .milliseconds(1200))
            env.daemon.onStatus = { _ in throw DaemonError.disconnected }
            try? await Task.sleep(for: .milliseconds(1200))
            w.close()
            for s in [DaemonManager.State.checking, .failed("down")] {
                let e = TestEnv()
                if case .failed = s {
                    e.daemon.onStatus = { _ in throw DaemonError.disconnected }
                    await e.app.daemon.refresh()
                }
                e.daemon.onStatus = { _ in throw CancellationError() }  // stays as it is
                let w2 = await render(IndexDetailsView().environmentObject(e.app), size: NSSize(width: 520, height: 600))
                w2.close()
                e.tearDown()
            }
        }

        @Test func searchLogShowsAndFilters() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.app.debugMode = true
            for q in ["alpha", "beta"] {
                env.app.search.query = q
                await env.app.search.refresh()
            }
            let w = await render(SearchLogView().environmentObject(env.app), size: NSSize(width: 760, height: 420), settle: .milliseconds(400))
            #expect(env.app.log.entries().count == 2)
            w.close()
        }
    }
}
