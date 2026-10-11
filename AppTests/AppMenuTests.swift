import AppKit
import FSearchKit
import Foundation
import Observation
import SwiftUI
import Testing

@testable import FSearch

extension AppTests {
    /// The panel's FSearch menu (⌘/ or the footer's gear).
    @Suite @MainActor
    struct AppMenuTests {
        private typealias P = PanelInput.Press
        private let slash = P(key: "/", characters: "/", command: true)

        /// Swaps the About and Quit seams for counters, so no test shows a window or quits the host.
        @MainActor private final class Seams {
            var abouts = 0, quits = 0
            private let about = AppMenuActions.showAbout, quit = AppMenuActions.quit
            init() {
                AppMenuActions.showAbout = { [unowned self] in abouts += 1 }
                AppMenuActions.quit = { [unowned self] in quits += 1 }
            }
            func restore() { (AppMenuActions.showAbout, AppMenuActions.quit) = (about, quit) }
        }

        @Test func linkRowsOpenTheirPagesAndHideThePanel() {
            let env = TestEnv()
            defer { env.tearDown() }
            let b = "https://github.com/domfahey/fsearch-app/blob/main/"
            let expected: [(PanelMenuAction, String)] = [
                (.manual, b + "docs/README.md"), (.keyboardShortcuts, b + "docs/reference/keyboard-shortcuts.md"),
                (.changelog, b + "CHANGELOG.md"), (.github, "https://github.com/domfahey/fsearch-app"),
                (.discussions, "https://github.com/domfahey/fsearch-app/discussions"),
            ]
            for (action, url) in expected {
                env.panel.isVisible = true
                let hides = env.panel.hides
                AppMenuActions.run(action, app: env.app)
                #expect(env.workspace.opened.last?.absoluteString == url, "\(action)")
                #expect(env.panel.hides == hides + 1 && !env.panel.isVisible, "\(action)")
            }
            #expect(env.workspace.opened.count == expected.count)
        }

        @Test func sendFeedbackOpensThePrefilledBugForm() {
            let env = TestEnv()
            defer { env.tearDown() }
            AppMenuActions.run(.sendFeedback, app: env.app)
            let url = env.workspace.opened.first?.absoluteString ?? ""
            #expect(url.hasPrefix(IssueReport.newIssueBase + "?template=bug_report.yml"))
            #expect(env.panel.hides == 1)
        }

        @Test func settingsAboutAndQuitGoThroughTheirSeams() {
            let env = TestEnv()
            defer { env.tearDown() }
            let seams = Seams()
            defer { seams.restore() }
            var settings = 0
            let saved = PanelController.openSettings
            PanelController.openSettings = { settings += 1 }
            defer { PanelController.openSettings = saved }

            AppMenuActions.run(.settings, app: env.app)
            #expect(settings == 1 && env.panel.hides == 1)
            AppMenuActions.run(.about, app: env.app)
            #expect(seams.abouts == 1 && env.panel.hides == 2)
            AppMenuActions.run(.quit, app: env.app)
            #expect(seams.quits == 1)
            #expect(env.workspace.opened.isEmpty)
        }

        /// The real About and Quit do nothing in the inert host, checked through their builders.
        @Test func theRealAboutAndQuitAreInertInTheTestHost() {
            #expect(Presentation.inert)
            var calls = 0
            AppMenuActions.live(inert: { true }, { calls += 1 })()
            #expect(calls == 0)
            AppMenuActions.live(inert: { false }, { calls += 1 })()
            #expect(calls == 1)
            // The default About is safe to call here: no window comes up.
            AppMenuActions.showAbout()
            #expect(!NSApp.windows.contains { $0.isVisible && $0.alphaValue > 0 && $0.title.contains("About") })
        }

        @Test func everyRowHasALinkOrAnAction() {
            for a in PanelMenuAction.allCases {
                switch a {
                case .manual, .keyboardShortcuts, .changelog, .github, .discussions: #expect(AppMenuActions.url(for: a) != nil, "\(a)")
                case .sendFeedback, .about, .settings, .quit: #expect(AppMenuActions.url(for: a) == nil, "\(a)")
                }
            }
        }

        @Test func commandSlashTogglesTheMenu() {
            let menu = AppMenuState()
            var ran: [PanelMenuAction] = []
            #expect(menu.handle(P(key: .downArrow), run: { ran.append($0) }) == nil)  // closed: the panel's key
            #expect(menu.handle(slash, run: { ran.append($0) }) == .handled)
            #expect(menu.isOpen)
            #expect(menu.handle(slash, run: { ran.append($0) }) == .handled)
            #expect(!menu.isOpen)
            #expect(ran.isEmpty)
        }

        @Test func keysDriveTheOpenMenu() {
            let menu = AppMenuState()
            var ran: [PanelMenuAction] = []
            let run: (PanelMenuAction) -> Void = { ran.append($0) }
            menu.toggle()
            // Typing and Backspace go to the filter field.
            #expect(menu.handle(P(key: "c", characters: "c"), run: run) == .ignored)
            #expect(menu.handle(P(key: .delete), run: run) == .ignored)
            #expect(menu.handle(P(key: "v", characters: "v", command: true), run: run) == .ignored)  // paste
            // Result keys do nothing while the menu is up.
            #expect(menu.handle(P(key: "k", characters: "k", command: true), run: run) == .handled)
            #expect(menu.isOpen && ran.isEmpty)
            #expect(menu.handle(P(key: .upArrow), run: run) == .handled)
            #expect(menu.model.selected?.action == .quit)
            #expect(menu.handle(P(key: "n", characters: "\u{0e}", control: true), run: run) == .handled)
            #expect(menu.model.selected?.action == .sendFeedback)
            menu.model.filter = "chan"
            #expect(menu.handle(P(key: .return), run: run) == .handled)
            #expect(ran == [.changelog] && !menu.isOpen)

            menu.toggle()
            menu.model.filter = "x"
            #expect(menu.handle(P(key: .escape), run: run) == .handled)
            #expect(menu.isOpen && menu.model.filter.isEmpty)
            #expect(menu.handle(P(key: .escape), run: run) == .handled)
            #expect(!menu.isOpen)
        }

        @Test func clickingARowRunsIt() {
            let menu = AppMenuState()
            var ran: [PanelMenuAction] = []
            menu.toggle()
            menu.choose(.github) { ran.append($0) }
            #expect(ran == [.github] && !menu.isOpen)
        }

        @Test func hidingThePanelClosesTheMenu() {
            let env = TestEnv()
            defer { env.tearDown() }
            let pc = PanelController()
            pc.show(app: env.app)
            pc.menu.toggle()
            #expect(pc.menu.isOpen)
            pc.hide(returnFocus: false)
            #expect(!pc.menu.isOpen)
            pc.show(app: env.app)
            #expect(!pc.menu.isOpen)  // a reopened panel never comes back with it open
            pc.hide(returnFocus: false)
        }

        @Test func theMenuDrawsInsideTheFixedPanelWithoutTheActionsMenu() async {
            let env = TestEnv()
            defer { env.tearDown() }
            var popped = 0
            let saved = ActionsMenu.popUp
            ActionsMenu.popUp = { _, _, _ in popped += 1 }
            defer { ActionsMenu.popUp = saved }
            let pc = PanelController()
            pc.show(app: env.app)
            defer { pc.hide(returnFocus: false) }
            #expect(pc.menu.handle(slash, run: { _ in }) == .handled)
            #expect(pc.menu.isOpen)
            try? await Task.sleep(for: .milliseconds(100))  // the panel renders the menu
            // The card shrinks with the filter inside the fixed-size panel.
            pc.menu.model.filter = "chan"
            try? await Task.sleep(for: .milliseconds(60))
            pc.menu.model.filter = "zzz"
            try? await Task.sleep(for: .milliseconds(60))
            #expect(popped == 0)
            #expect(pc.panel?.frame.size == NSSize(width: 680, height: 460))
        }

        @Test func versionHeaderReadsTheBundle() {
            let version = AppMenuActions.version().version
            #expect(!version.isEmpty)
            #expect(AppMenuActions.header().hasPrefix("FSearch v\(version)"))
        }

        /// ↵ held for a slow search, then the menu opens (⌘/ or the gear): the key never runs behind the menu.
        @Test func openingTheMenuDropsAHeldKey() async {
            let env = TestEnv()
            defer { env.tearDown() }
            env.daemon.onSearch = { q in SearchReply(tookUs: 1, hits: [Wire.hit("/p/\(q).txt")]) }
            let pc = PanelController()
            pc.show(app: env.app)
            defer { pc.hide(returnFocus: false) }
            env.app.search.query = "slow"  // its search hasn't answered
            #expect(PanelInput.gate(.enter, held: &pc.held.key, model: env.app.search) == nil)
            #expect(pc.held.key.held == .enter)
            #expect(pc.menu.handle(slash, run: { _ in }) == .handled)  // ⌘/
            #expect(pc.held.key.held == nil)
            // The results land: nothing to replay.
            await env.app.search.refresh()
            #expect(await eventually { PanelInput.rowsAreCurrent(env.app.search) })
            #expect(PanelInput.replay(held: &pc.held.key, model: env.app.search, visible: true) == nil)
            #expect(env.workspace.opened.isEmpty)

            // The gear takes the same path.
            pc.menu.close()
            env.app.search.query = "slower"
            #expect(PanelInput.gate(.cmdK, held: &pc.held.key, model: env.app.search) == nil)
            pc.menu.toggle()
            #expect(pc.held.key.held == nil)
        }

        /// Tab would move the keyboard to the search field behind the menu.
        @Test func tabStaysInTheOpenMenu() {
            let menu = AppMenuState()
            #expect(menu.handle(P(key: .tab), run: { _ in }) == nil)  // closed: the panel's
            menu.toggle()
            #expect(menu.handle(P(key: .tab), run: { _ in }) == .handled)
            #expect(menu.handle(P(key: .tab, shift: true), run: { _ in }) == .handled)
            #expect(menu.isOpen)
        }

        /// The panel watches only open/closed, so typing in the filter or hovering never redraws the whole panel.
        @Test func isOpenChangesOnlyOnOpenAndClose() {
            let menu = AppMenuState()
            final class Count: @unchecked Sendable { var n = 0 }
            let count = Count()
            var changes: Int { count.n }
            func watch() {
                withObservationTracking {
                    _ = menu.isOpen
                } onChange: {
                    count.n += 1
                }
            }
            watch()
            menu.toggle()
            #expect(changes == 1 && menu.isOpen)
            watch()
            menu.model.filter = "chan"
            menu.model.select(.changelog)
            _ = menu.handle(P(key: .downArrow), run: { _ in })
            #expect(changes == 1)
            _ = menu.handle(P(key: .escape), run: { _ in })  // clears the filter only
            #expect(changes == 1)
            _ = menu.handle(P(key: .escape), run: { _ in })
            #expect(changes == 2 && !menu.isOpen)
        }

        /// Render smoke test: the menu open, filtered, and empty, plus the gear (for coverage).
        @Test func menuViewsRenderSmoke() async {
            let menu = AppMenuState()
            menu.toggle()
            var ran: [PanelMenuAction] = []
            // Fixed frames: the card's height follows the filter, and a test window sized to fit would chase it.
            let view = AppMenuView(menu: menu, run: { ran.append($0) }).frame(width: 320, height: 420)
            let w = await render(view, size: NSSize(width: 320, height: 420))
            defer { w.close() }
            menu.model.filter = "chan"
            try? await Task.sleep(for: .milliseconds(60))
            menu.model.filter = "zzz"
            try? await Task.sleep(for: .milliseconds(60))
            #expect(menu.model.isEmpty)
            let g = await render(AppMenuButton(menu: menu).frame(width: 120, height: 30), size: NSSize(width: 120, height: 30))
            defer { g.close() }
            #expect(w.canBecomeKey == false && g.canBecomeKey == false)
            #expect(ran.isEmpty)
        }
    }
}
