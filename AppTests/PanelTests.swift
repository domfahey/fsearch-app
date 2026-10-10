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
            pc.perform(.copyPath(3), items)  // no such row
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

        /// The search view in every state the panel can show.
        @Test func searchViewStates() async {
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
            for (q, mode) in [("heron", SearchMode.names), ("re:(", .names), ("?", .names), ("needle", .content),
                              ("handler", .symbols), ("grep:needle", .names), ("ext:swift", .content)] {
                app.search.mode = mode
                app.search.query = q
                await app.search.refresh()
                try? await Task.sleep(for: .milliseconds(60))
            }
            #expect(app.search.phase == .idle)  // filter-only content query waits
            app.showActionError("Couldn't open")
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
            try? await Task.sleep(for: .milliseconds(100))
            pc.hide(returnFocus: false)
        }

        @Test func resultsAndDisconnectsDriveTheRestartBudget() async {
            let env = TestEnv()
            defer { env.tearDown() }
            let status = MenuBarStatus.shared
            status.restartBudget = RestartBudget(max: 2)
            status.recoveryCheck = RecoveryCheck(interval: 0)
            let pc = PanelController()
            pc.show(app: env.app)
            // A daemon marked failed while searches work gets re-checked.
            env.daemon.onStatus = { n in if n <= 50 { throw DaemonError.disconnected }; return Wire.status() }
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
            env.daemon.onSearch = { _ in throw DaemonError.disconnected }
            env.app.search.query = "ab"
            await env.app.search.refresh()
            let spent = await eventually { status.restartBudget.used == 2 }
            #expect(spent, "used=\(status.restartBudget.used) phase=\(env.app.search.phase)")
            try? await Task.sleep(for: .milliseconds(200))
            #expect(status.restartBudget.used == 2)
            // In test mode a restart only re-checks the daemon.
            #expect(env.daemon.statuses >= statusCalls + 2)

            // Results again refill it.
            env.daemon.onSearch = { _ in SearchReply(tookUs: 1, hits: [Wire.hit("/p/a")]) }
            env.app.search.query = "abc"
            await env.app.search.refresh()
            #expect(await eventually { status.restartBudget.used == 0 })
            pc.hide(returnFocus: false)
            status.restartBudget = RestartBudget()
            status.recoveryCheck = RecoveryCheck()
        }
    }
}
