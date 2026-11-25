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
            let missing = AppMenuActions.version(info: nil)
            #expect(missing.version == "unknown" && missing.build == "")
            let custom = AppMenuActions.version(info: ["CFBundleShortVersionString": "1.2.3", "CFBundleVersion": "42"])
            #expect(custom.version == "1.2.3" && custom.build == "42")
        }

        @Test func performAboutActivatesBeforeOrderingAboutPanel() {
            var events: [String] = []
            AppMenuActions.performAbout(activate: { events.append("activate") }, orderFront: { events.append("about") })
            #expect(events == ["activate", "about"])
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

        /// Tab would move the keyboard to the search field behind the menu; ⌃Y (ASCII EM, also 0x19) is not BackTab.
        @Test func tabStaysInTheOpenMenu() {
            let menu = AppMenuState()
            #expect(menu.handle(P(key: .tab), run: { _ in }) == nil)  // closed: the panel's
            menu.toggle()
            #expect(menu.handle(P(key: .tab), run: { _ in }) == .handled)
            #expect(menu.handle(P(key: .tab, shift: true), run: { _ in }) == .handled)
            #expect(menu.handle(P(key: KeyEquivalent("\u{19}"), characters: "\u{19}", shift: true), run: { _ in }) == .handled)
            #expect(menu.handle(P(key: KeyEquivalent("\u{19}"), characters: "\u{19}", control: true), run: { _ in }) == .ignored)
            #expect(menu.isOpen)
        }

        /// ⌥↵, ⌃↵, rejected modifier combos and held repeats must not reach the filter field.
        @Test func rejectedShortcutsAndRepeatsAreSwallowedWhileOpen() {
            let menu = AppMenuState()
            var ran: [PanelMenuAction] = []
            let run: (PanelMenuAction) -> Void = { ran.append($0) }
            menu.toggle()
            #expect(menu.handle(P(key: .return, option: true), run: run) == .handled)
            #expect(menu.handle(P(key: .return, control: true), run: run) == .handled)
            #expect(menu.handle(P(key: "y", characters: "\u{19}", command: true, control: true, keyCode: 0x10), run: run) == .handled)
            #expect(menu.handle(P(key: "/", characters: "/", command: true, control: true, keyCode: 0x2C), run: run) == .handled)
            #expect(menu.handle(P(key: .return, isRepeat: true), run: run) == .handled)
            #expect(menu.handle(P(key: .escape, isRepeat: true), run: run) == .handled)
            #expect(menu.handle(P(key: "/", characters: "/", command: true, isRepeat: true), run: run) == .handled)
            #expect(menu.isOpen && ran.isEmpty)
        }

        /// Clicking non-interactive parts of the menu card (header, padding) must not fall through to the backdrop and close it.
        @Test func clickingInsideTheMenuCardKeepsItOpen() async throws {
            final class ClickableHost<V: View>: NSHostingView<V> {
                override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
            }
            let menu = AppMenuState()
            menu.toggle()
            var ran: [PanelMenuAction] = []
            let overlay = AppMenuOverlay(menu: menu) { ran.append($0) }.frame(width: 680, height: 460)
            let w = HostSafeWindow(
                contentRect: NSRect(origin: offscreenOrigin, size: NSSize(width: 680, height: 460)),
                styleMask: [.borderless], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = ClickableHost(rootView: overlay)
            w.setFrameOrigin(offscreenOrigin)
            Presentation.present(w, inert: true)
            defer { w.close() }
            let header = try #require(await axWait(id: "appMenuHeader", in: w))
            let card = try #require(axNode(id: "appMenu", in: w))
            let field = try #require(axNode(id: "appMenuField", in: w))
            let community = try #require(axNode("Community", in: w))
            let changelog = try #require(axNode(id: "appMenu-Changelog", in: w))
            let bounds = NSRect(x: 0, y: 0, width: 680, height: 460)
            let headerRect = w.convertFromScreen(header.frame)
            let cardRect = w.convertFromScreen(card.frame)
            let fieldRect = w.convertFromScreen(field.frame)
            let communityRect = w.convertFromScreen(community.frame)
            let changelogRect = w.convertFromScreen(changelog.frame)
            #expect(bounds.contains(cardRect), "cardRect \(cardRect) not in window bounds \(bounds)")
            let insidePoints = [
                ("header", NSPoint(x: headerRect.midX, y: headerRect.midY)),
                ("headerRight", NSPoint(x: cardRect.maxX - 10, y: headerRect.midY)),
                ("community", NSPoint(x: communityRect.midX, y: communityRect.midY)),
                ("fieldPadding", NSPoint(x: cardRect.minX + 4, y: fieldRect.midY)),
            ]
            for (name, pt) in insidePoints {
                #expect(cardRect.contains(pt), "\(name) \(pt) outside \(cardRect)")
                try click(at: pt, in: w)
                try? await Task.sleep(for: .milliseconds(50))
                #expect(menu.isOpen, "clicking \(name) at \(pt) (card=\(cardRect)) dismissed the menu")
            }

            // Clicking a row actually runs it (proves clicks land at these coordinates).
            try click(at: NSPoint(x: changelogRect.midX, y: changelogRect.midY), in: w)
            #expect(await eventually { ran == [.changelog] && !menu.isOpen })

            // Reopen and verify clicking outside the card closes it.
            menu.toggle()
            #expect(await axWait(id: "appMenuHeader", in: w) != nil)
            let outside = NSPoint(x: 600, y: 400)
            #expect(!cardRect.contains(outside))
            try click(at: outside, in: w)
            #expect(await eventually { !menu.isOpen }, "clicking the backdrop must close the menu")
        }

        /// GitHub's detail text reaches the row's right edge, aligned with the shortcut keycap box (no phantom trailing spacing).
        @Test func detailTextAlignsWithShortcutKeycaps() async throws {
            let items = PanelMenuModel.sections.flatMap(\.items)
            let github = try #require(items.first { $0.action == .github })
            let settings = try #require(items.first { $0.action == .settings })
            let stack = VStack(spacing: 0) {
                AppMenuRowLabel(item: settings).frame(width: 272, height: 26)
                AppMenuRowLabel(item: github).frame(width: 272, height: 26)
            }
            let w = await render(stack, size: NSSize(width: 272, height: 52))
            defer { w.close() }
            let detail = try #require(await axWait("domfahey/fsearch-app", in: w))
            let keycap = try #require(axNode(",", in: w))
            // Keycap centers "," inside a 20 pt wide box (minWidth 18 + 1 pt horizontal padding each side).
            let keycapRightEdge = keycap.frame.midX + 10
            #expect(abs(detail.frame.maxX - w.frame.maxX) <= 1, "detail=\(detail.frame.maxX) rowRight=\(w.frame.maxX)")
            #expect(abs(detail.frame.maxX - keycapRightEdge) <= 1, "detail=\(detail.frame.maxX) keycapRight=\(keycapRightEdge)")
        }

        private func click(at point: NSPoint, in w: NSWindow) throws {
            let down = try #require(
                NSEvent.mouseEvent(
                    with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            let up = try #require(
                NSEvent.mouseEvent(
                    with: .leftMouseUp, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + 0.01,
                    windowNumber: w.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
            w.sendEvent(down)
            w.sendEvent(up)
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

        /// Opening the menu resigns search-field focus immediately and defers menu filter-field focus;
        /// closing resigns menu focus and defers search-field restoration, regardless of callback order.
        @Test func focusCoordinatorHandsFocusToMenuOnOpenAndBackOnClose() {
            @MainActor final class State {
                var pending: [@MainActor () -> Void] = []
                var visible = true
                var menuOpen = false
                var searchFocused = true
                var menuFocused = false
                func flushAll() {
                    while !pending.isEmpty { pending.removeFirst()() }
                }
            }
            let s = State()
            let coordinator = PanelFocusCoordinator { s.pending.append($0) }

            // Opening: SearchView resigns immediately; AppMenuView defers claiming focus.
            s.menuOpen = true
            coordinator.handleMenuOpenChanged(
                true, isVisible: { s.visible }, isMenuOpen: { s.menuOpen }, setSearchFocused: { s.searchFocused = $0 })
            #expect(!s.searchFocused, "opening the menu must resign search-field focus immediately")
            #expect(s.pending.isEmpty)

            coordinator.requestMenuFocus(isMenuOpen: { s.menuOpen }, setFocused: { s.menuFocused = $0 })
            #expect(!s.menuFocused, "menu filter focus must be deferred to the next main-queue turn")
            #expect(s.pending.count == 1)
            s.pending.removeFirst()()
            #expect(s.menuFocused && !s.searchFocused)

            // Closing: AppMenuView clears on disappear; SearchView defers restoring focus.
            s.menuOpen = false
            coordinator.clearMenuFocus { s.menuFocused = $0 }
            #expect(!s.menuFocused)
            coordinator.handleMenuOpenChanged(
                false, isVisible: { s.visible }, isMenuOpen: { s.menuOpen }, setSearchFocused: { s.searchFocused = $0 })
            #expect(!s.searchFocused, "closing the menu must defer search-field focus restoration")
            #expect(s.pending.count == 1)
            s.pending.removeFirst()()
            #expect(s.searchFocused && !s.menuFocused)

            // Order independence: AppMenuView.onAppear before SearchView.onChange(true),
            // and SearchView.onChange(false) before AppMenuView.onDisappear.
            s.menuOpen = true
            coordinator.requestMenuFocus(isMenuOpen: { s.menuOpen }, setFocused: { s.menuFocused = $0 })
            coordinator.handleMenuOpenChanged(
                true, isVisible: { s.visible }, isMenuOpen: { s.menuOpen }, setSearchFocused: { s.searchFocused = $0 })
            #expect(!s.searchFocused && !s.menuFocused)
            s.flushAll()
            #expect(s.menuFocused && !s.searchFocused)

            s.menuOpen = false
            coordinator.handleMenuOpenChanged(
                false, isVisible: { s.visible }, isMenuOpen: { s.menuOpen }, setSearchFocused: { s.searchFocused = $0 })
            coordinator.clearMenuFocus { s.menuFocused = $0 }
            #expect(!s.searchFocused && !s.menuFocused)
            s.flushAll()
            #expect(s.searchFocused && !s.menuFocused)
        }

        /// Stale deferred focus callbacks must be ignored after rapid open/close toggles or hiding the panel.
        @Test func focusCoordinatorDropsStaleDeferredCallbacks() {
            @MainActor final class State {
                var pending: [@MainActor () -> Void] = []
                var visible = true
                var menuOpen = false
                var searchFocused = false
                var menuFocused = false
                var firstMenuFocused = false
                var secondMenuFocused = false
                func flushAll() {
                    while !pending.isEmpty { pending.removeFirst()() }
                }
            }
            let s = State()
            let coordinator = PanelFocusCoordinator { s.pending.append($0) }

            // 1. Panel opens (queues search focus), then menu opens before that async turn runs.
            coordinator.requestSearchFocus(isVisible: { s.visible }, isMenuOpen: { s.menuOpen }, setFocused: { s.searchFocused = $0 })
            s.menuOpen = true
            coordinator.handleMenuOpenChanged(
                true, isVisible: { s.visible }, isMenuOpen: { s.menuOpen }, setSearchFocused: { s.searchFocused = $0 })
            coordinator.requestMenuFocus(isMenuOpen: { s.menuOpen }, setFocused: { s.menuFocused = $0 })
            #expect(s.pending.count == 2)
            s.flushAll()
            #expect(!s.searchFocused && s.menuFocused)

            // 2. Menu opens then closes before the async turn runs: menu field is NOT focused, search field IS.
            s.searchFocused = false
            s.menuFocused = false
            s.menuOpen = true
            coordinator.handleMenuOpenChanged(
                true, isVisible: { s.visible }, isMenuOpen: { s.menuOpen }, setSearchFocused: { s.searchFocused = $0 })
            coordinator.requestMenuFocus(isMenuOpen: { s.menuOpen }, setFocused: { s.menuFocused = $0 })
            s.menuOpen = false
            coordinator.clearMenuFocus { s.menuFocused = $0 }
            coordinator.handleMenuOpenChanged(
                false, isVisible: { s.visible }, isMenuOpen: { s.menuOpen }, setSearchFocused: { s.searchFocused = $0 })
            s.flushAll()
            #expect(!s.menuFocused && s.searchFocused)

            // 3. Rapid open -> close -> open before any async turn runs: only the latest menu view gets focus.
            s.searchFocused = false
            s.menuOpen = true
            coordinator.handleMenuOpenChanged(
                true, isVisible: { s.visible }, isMenuOpen: { s.menuOpen }, setSearchFocused: { s.searchFocused = $0 })
            coordinator.requestMenuFocus(isMenuOpen: { s.menuOpen }, setFocused: { s.firstMenuFocused = $0 })
            s.menuOpen = false
            coordinator.clearMenuFocus { s.firstMenuFocused = $0 }
            coordinator.handleMenuOpenChanged(
                false, isVisible: { s.visible }, isMenuOpen: { s.menuOpen }, setSearchFocused: { s.searchFocused = $0 })
            s.menuOpen = true
            coordinator.handleMenuOpenChanged(
                true, isVisible: { s.visible }, isMenuOpen: { s.menuOpen }, setSearchFocused: { s.searchFocused = $0 })
            coordinator.requestMenuFocus(isMenuOpen: { s.menuOpen }, setFocused: { s.secondMenuFocused = $0 })
            s.flushAll()
            #expect(!s.firstMenuFocused, "stale open callback from the closed menu view must not fire")
            #expect(!s.searchFocused, "stale close callback must not steal focus after reopening")
            #expect(s.secondMenuFocused)

            // 4. Panel hides before close's async turn runs: search field is NOT focused.
            s.searchFocused = false
            s.menuOpen = false
            coordinator.clearMenuFocus { s.secondMenuFocused = $0 }
            coordinator.handleMenuOpenChanged(
                false, isVisible: { s.visible }, isMenuOpen: { s.menuOpen }, setSearchFocused: { s.searchFocused = $0 })
            s.visible = false
            s.flushAll()
            #expect(!s.searchFocused, "closing the menu while hiding the panel must not focus the search field")
        }

        /// Hosted SearchView + AppMenuOverlay exercises open -> close deferred focus scheduling in the inert host.
        @Test func searchViewMenuToggleSchedulesDeferredFocusInInertHost() async throws {
            @MainActor final class Queue {
                var pending: [@MainActor () -> Void] = []
                func flushAll() {
                    while !pending.isEmpty { pending.removeFirst()() }
                }
            }
            let env = TestEnv()
            defer { env.tearDown() }
            let menu = AppMenuState()
            let queue = Queue()
            let coordinator = PanelFocusCoordinator { queue.pending.append($0) }
            let view = SearchView(
                model: env.app.search, state: PanelState(), held: HeldKeyBox(), keys: PanelKeyFeed(), geometry: PanelGeometry(),
                menu: menu, isVisible: { true }, focusCoordinator: coordinator,
                onEffect: { _, _ in }, onSelect: { _ in }, onCommand: { _ in }
            ).environmentObject(env.app)
            let w = await render(view, size: NSSize(width: 680, height: 460))
            defer { w.close() }
            #expect(w.canBecomeKey == false)
            // Initial SearchView.onAppear deferred search-field focus.
            #expect(await eventually { !queue.pending.isEmpty })
            queue.flushAll()

            // Opening the menu mounts AppMenuView and queues a deferred menu-field focus callback.
            menu.toggle()
            #expect(await axWait(id: "appMenuField", in: w) != nil)
            #expect(await eventually { queue.pending.count == 1 })
            queue.flushAll()

            // Closing unmounts AppMenuView (clearing menu focus) and queues a deferred search-field restoration.
            menu.toggle()
            #expect(await eventually { axNode(id: "appMenuField", in: w) == nil })
            #expect(await eventually { queue.pending.count == 1 })
            queue.flushAll()

            // Default scheduler path through PanelController also toggles open -> close cleanly in the inert host.
            let pc = PanelController()
            pc.show(app: env.app)
            defer { pc.hide(returnFocus: false) }
            pc.menu.toggle()
            let panel = try #require(pc.panel)
            #expect(await axWait(id: "appMenuField", in: panel) != nil)
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } }
            pc.menu.toggle()
            #expect(await eventually { axNode(id: "appMenuField", in: panel) == nil })
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in DispatchQueue.main.async { c.resume() } }
            #expect(!pc.menu.isOpen && panel.canBecomeKey == false)
        }
    }
}
