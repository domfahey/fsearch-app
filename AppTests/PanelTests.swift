import AppKit
import FSearchKit
import Foundation
import SwiftUI
import Testing

@testable import FSearch

extension AppTests {
    @Suite @MainActor
    struct PanelControllerTests {
        @Test func theTestHostsPanelCanNeverBecomeKey() {
            let env = TestEnv()
            defer { env.tearDown() }
            let pc = PanelController()
            pc.show(app: env.app)
            defer { pc.hide(returnFocus: false) }
            #expect(pc.panel?.canBecomeKey == false)
            #expect(pc.panel?.isKeyWindow == false)
            #expect(pc.panel?.alphaValue == 0)
        }

        @Test func showHideResumesTheSession() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.daemon.onSearch = { q in SearchReply(tookUs: 500, hits: [Wire.hit("/p/\(q).txt"), Wire.hit("/p/\(q)2.txt")]) }
            let pc = PanelController()
            #expect(!pc.isVisible)
            pc.show(app: env.app)
            #expect(pc.isVisible)
            #expect(pc.panel?.isFloatingPanel == true)
            #expect(pc.panel?.canBecomeKey == false)  // inert host
            #expect(env.app.search.query == "")
            env.app.search.query = "heron"
            env.app.search.mode = .content
            pc.hide(returnFocus: false)
            #expect(!pc.isVisible)
            pc.hide(returnFocus: false)  // already hidden: no-op
            // Reopening within a minute resumes the query and mode.
            pc.toggle(app: env.app)
            #expect(pc.isVisible)
            #expect(env.app.search.query == "heron")
            #expect(env.app.search.mode == .content)
            pc.toggle(app: env.app)
            #expect(!pc.isVisible)
        }

        @Test func hidingThePanelDropsAHeldKey() {
            let env = TestEnv()
            defer { env.tearDown() }
            let pc = PanelController()
            pc.show(app: env.app)
            env.app.search.query = "slow"  // its search hasn't answered
            #expect(PanelInput.gate(.enter, held: &pc.held.key, model: env.app.search) == nil)
            #expect(pc.held.key.held == .enter)
            pc.hide(returnFocus: false)
            #expect(pc.held.key.held == nil)
        }

        /// `-UITestShowPanel` is read from the app's own options, not the process's.
        @Test func thePanelFollowsTheAppsShowPanelOption() {
            let env = TestEnv()
            defer { env.tearDown() }
            let plain = PanelController()
            plain.install(app: env.app)
            #expect(!plain.isVisible)
            var options = env.app.options
            options.showPanel = true
            let app = AppState(
                options: options, defaults: env.defaults, helper: nil,
                names: env.daemon, content: env.daemon, control: env.daemon, clock: env.clock.clock,
                cliAgentInstalled: { false })
            app.panel = env.panel
            let pc = PanelController()
            pc.install(app: app)
            defer { pc.hide(returnFocus: false) }
            #expect(pc.isVisible)
            // It stays up when it loses key, as UI tests need.
            pc.panel?.resignKey()
            #expect(pc.isVisible)
        }

        @Test func effectsRunTheirActions() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let pc = PanelController()
            let path = env.file("x.txt")
            let items: [ResultItem] = [.file(Wire.hit(path))]
            pc.perform(.none, items)  // no app yet: ignored
            pc.show(app: env.app)
            pc.perform(.copyPath(0), items)
            #expect(env.pasteboard.string(forType: .string) == path)
            #expect(pc.isVisible)  // copying stays in the launcher
            let count = env.pasteboard.changeCount
            pc.perform(.copyPath(3), items)  // no such row
            #expect(env.pasteboard.changeCount == count)
            #expect(pc.isVisible)
            pc.perform(.reveal(0), items)
            #expect(env.workspace.revealed == [[URL(fileURLWithPath: path)]])
            #expect(!pc.isVisible)
            pc.show(app: env.app)
            pc.perform(.open(0), items)
            #expect(env.workspace.opened == [URL(fileURLWithPath: path)])
            #expect(env.app.recents.paths == [path])
            #expect(!pc.isVisible)
            pc.show(app: env.app)
            pc.perform(.none, items)
            #expect(pc.isVisible)
            pc.perform(.hide, items)
            #expect(!pc.isVisible)
        }

        /// Item 9: ↵ or ⌘↵ on a result that is gone: an error, the launcher stays, no recent.
        @Test func missingFileKeepsTheLauncherUp() {
            let env = TestEnv()
            defer { env.tearDown() }
            let pc = PanelController()
            env.workspace.missing = ["/p/gone.txt"]
            let items: [ResultItem] = [.file(Wire.hit("/p/gone.txt"))]
            pc.show(app: env.app)
            defer { pc.hide(returnFocus: false) }
            let g = env.app.recentsGeneration
            pc.perform(.open(0), items)
            #expect(env.app.actionError == "“gone.txt” is gone: moved or deleted")
            #expect(pc.isVisible)
            #expect(env.app.recentsGeneration == g)  // nothing recorded
            pc.perform(.reveal(0), items)
            #expect(pc.isVisible)
            #expect(env.workspace.opened.isEmpty && env.workspace.revealed.isEmpty)
        }

        /// A-M2: ↵ on an app reveals it in Finder instead of launching it.
        @Test func returnOnALaunchableFileReveals() {
            let env = TestEnv()
            defer { env.tearDown() }
            let pc = PanelController()
            let items: [ResultItem] = [.file(Wire.hit("/p/Tool.app"))]
            pc.show(app: env.app)
            pc.perform(.open(0), items)
            #expect(env.workspace.revealed == [[URL(fileURLWithPath: "/p/Tool.app")]])
            #expect(env.workspace.opened.isEmpty)
            #expect(!pc.isVisible)
        }

        /// Item 5: the panel lands inside the screen's visible frame.
        @Test func panelFitsTheScreen() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let pc = PanelController()
            pc.show(app: env.app)
            defer { pc.hide(returnFocus: false) }
            let frame = try #require(pc.panel?.frame)
            // A host with no screen (headless CI) places nothing to check.
            guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main else { return }
            #expect(screen.visibleFrame.contains(frame), "\(frame) outside \(screen.visibleFrame)")
        }

        /// Render smoke test: the search view in every state the panel can
        /// show (for coverage); each query's model state is checked.
        @Test func searchViewStatesRenderSmoke() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let app = env.app
            env.daemon.onSearch = { q in
                if q.hasPrefix("re:(") { throw DaemonError.daemon("regex parse error") }
                return SearchReply(tookUs: 500, hits: [Wire.hit("/p/\(q).txt"), Wire.hit("/p/folder")])
            }
            env.daemon.onGrep = { _, pattern, _ in Wire.grep([("/p/main.swift", [(3, "  func \(pattern)() {}")])]) }
            let pc = PanelController()
            pc.show(app: app)
            app.openedRecent(env.file("recent.txt"))
            try? await Task.sleep(for: .milliseconds(100))

            app.debugMode = true
            for (q, mode) in [
                ("heron", SearchMode.names), ("re:(", .names), ("?", .names), ("needle", .content),
                ("handler", .symbols), ("grep:needle", .names), ("ext:swift", .content),
            ] {
                app.search.mode = mode
                app.search.query = q
                await app.search.refresh()
                // The view's own refresh (on the query change) may still be in flight.
                let settled = await eventually {
                    switch q {
                    case "re:(": app.search.phase == .failed(.daemon("regex parse error"))
                    case "?", "ext:swift": app.search.phase == .idle  // cheat sheet; filter-only content query waits
                    default: app.search.phase == .results && !app.search.items.isEmpty
                    }
                }
                #expect(settled, "\(q): \(app.search.phase)")
                try? await Task.sleep(for: .milliseconds(60))
            }
            app.showActionError("Couldn't open")
            #expect(app.actionError == "Couldn't open")
            try? await Task.sleep(for: .milliseconds(60))
            pc.hide(returnFocus: false)
            app.debugMode = false
        }

        @Test func indexingPhaseShowsAndPolls() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.daemon.onSearch = { _ in throw DaemonError.indexing("indexing 5%") }
            env.daemon.onStatus = { _ in throw DaemonError.indexing("indexing 5%") }
            let pc = PanelController()
            pc.show(app: env.app)
            env.app.search.query = "x"
            await env.app.search.refresh()
            #expect(await eventually { env.app.search.phase == .indexing })
            // The message line polls the daemon (every ~2 s) while the panel is up.
            let polled = await eventually(.seconds(5)) { env.daemon.statuses >= 1 }
            #expect(polled, "the message line never polled: phase=\(env.app.search.phase)")
            pc.hide(returnFocus: false)
        }

        /// Not a view behaviour: AppState reacts to every finished search, so a
        /// repeated .failed(.disconnected) (which a phase-change observer in
        /// the view could miss when .loading is never rendered) spends the
        /// budget each time.
        @Test func resultsAndDisconnectsDriveTheRestartBudget() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let status = MenuBarStatus(defaults: env.defaults)
            status.restartBudget = RestartBudget(max: 2)
            status.recoveryCheck = RecoveryCheck(interval: 0)
            env.app.status = status
            // A daemon marked failed while searches work gets re-checked.
            env.daemon.onStatus = { n in
                if n <= 50 { throw DaemonError.disconnected }; return Wire.status()
            }
            await env.app.daemon.refresh()
            #expect(env.app.daemon.state == .failed("The search helper isn't answering."))

            // Results while it is marked failed: re-checked, and it is back.
            env.daemon.onSearch = { _ in SearchReply(tookUs: 1, hits: [Wire.hit("/p/a")]) }
            env.app.search.query = "a"
            await env.app.search.refresh()
            #expect(await eventually { env.app.daemon.state == .running(Wire.status()) })

            // A dropped connection restarts (each restart re-searches, which
            // fails again) until the outage's budget is spent, then stops.
            let statusCalls = env.daemon.statuses
            let searches = env.daemon.searches.count
            env.daemon.onSearch = { _ in throw DaemonError.disconnected }
            env.app.search.query = "ab"
            await env.app.search.refresh()
            let spent = await eventually { status.restartBudget.used == 2 && env.daemon.searches.count == searches + 3 }
            #expect(spent, "used=\(status.restartBudget.used) searches=\(env.daemon.searches.count - searches)")
            // In test mode a restart only re-checks the daemon: one status call each.
            #expect(await eventually { env.daemon.statuses == statusCalls + 2 })
            let afterBudget = (env.daemon.statuses, env.daemon.searches.count)
            try? await Task.sleep(for: .milliseconds(200))
            #expect(status.restartBudget.used == 2)
            #expect(env.daemon.statuses == afterBudget.0, "no restart once the budget is spent")
            #expect(env.daemon.searches.count == afterBudget.1)

            // Results again refill it.
            env.daemon.onSearch = { _ in SearchReply(tookUs: 1, hits: [Wire.hit("/p/a")]) }
            env.app.search.query = "abc"
            await env.app.search.refresh()
            #expect(status.restartBudget.used == 0)
        }
    }
}
