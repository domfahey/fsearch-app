import AppKit
import FSearchKit
import Foundation
import Testing

@testable import FSearch

extension AppTests {
    /// Handling of `fsearch://` URLs: Info.plist registration, panel presentation,
    /// cold-launch buffering in AppDelegate, and rejection of unrecognized URLs.
    @Suite @MainActor
    struct URLSchemeTests {
        @Test func infoPlistRegistersFSearchURLScheme() throws {
            let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
            let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            #expect(schemes.contains("fsearch"))
        }

        @Test func openURLShowsPanelWithQueryModeAndResetsSelection() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            env.daemon.onGrep = { _, pattern, mode in
                Wire.grep([("/p/main.swift", [(12, "func \(pattern)() // \(mode)")])])
            }
            let pc = PanelController()
            defer { pc.hide(returnFocus: false) }

            // Seed a prior hidden session so we verify the URL replaces resumed state.
            pc.show(app: env.app)
            env.app.search.query = "stale"
            env.app.search.mode = .names
            pc.viewState.state.selection = 3
            pc.hide(returnFocus: false)

            let url = try #require(URL(string: "fsearch://search?q=SearchModel&mode=symbols"))
            #expect(pc.open(url: url, app: env.app))
            #expect(pc.isVisible)
            #expect(env.app.search.query == "SearchModel")
            #expect(env.app.search.mode == .symbols)
            #expect(pc.selection == 0)
            #expect(pc.viewState.state.selection == 0)
            #expect(await eventually { env.app.search.phase == .results && env.daemon.greps.last?.mode == .symbol })
        }

        @Test func openURLUpdatesAlreadyVisiblePanelClosesMenuAndCancelsHeldKey() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            env.daemon.onSearch = { q in SearchReply(tookUs: 200, hits: [Wire.hit("/p/\(q).txt")]) }
            let pc = PanelController()
            defer { pc.hide(returnFocus: false) }

            pc.show(app: env.app)
            env.app.search.query = "first"
            #expect(PanelInput.gate(.enter, held: &pc.held.key, model: env.app.search) == nil)
            #expect(pc.held.key.held == .enter)
            pc.menu.toggle()
            #expect(pc.menu.isOpen)
            let focusBefore = pc.viewState.focusTrigger

            let url = try #require(URL(string: "fsearch://search?q=second%20ext%3Atxt"))
            #expect(pc.open(url: url, app: env.app))
            #expect(pc.isVisible, "already-visible panel must stay visible and update, not toggle closed")
            #expect(!pc.menu.isOpen, "opening a search URL must dismiss the FSearch menu")
            #expect(pc.held.key.held == nil, "a key held for the old query must never fire on the URL's results")
            #expect(env.app.search.query == "second ext:txt")
            #expect(env.app.search.mode == .names)
            #expect(pc.viewState.focusTrigger > focusBefore)
            #expect(await eventually { env.daemon.searches.contains("second ext:txt") })
        }

        /// Another app can plant a result and open the panel just as ↵ is pressed for something else.
        @Test func externalShowsIgnoreActivationKeysForHalfASecondButUserShowsDoNot() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let pc = PanelController()
            defer { pc.hide(returnFocus: false) }
            var now = ContinuousClock.now
            pc.uptime = { now }

            let url = try #require(URL(string: "fsearch://search?q=planted"))
            #expect(pc.open(url: url, app: env.app))
            #expect(PanelInput.ignoresActivation(.enter, held: pc.held, at: now))
            #expect(PanelInput.ignoresActivation(.cmdDigit(1), held: pc.held, at: now))
            #expect(!PanelInput.ignoresActivation(.down, held: pc.held, at: now))
            now = now.advanced(by: ExternalOpenGuard.window)
            #expect(!PanelInput.ignoresActivation(.enter, held: pc.held, at: now))

            // The reopen notification path.
            pc.showExternally(app: env.app)
            #expect(PanelInput.ignoresActivation(.enter, held: pc.held, at: now))

            // The hotkey/menu path disarms it.
            pc.hide(returnFocus: false)
            pc.show(app: env.app)
            #expect(!PanelInput.ignoresActivation(.enter, held: pc.held, at: now))
        }

        @Test func openURLIgnoresUnrecognizedURLsWithoutShowingPanel() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let pc = PanelController()
            defer { pc.hide(returnFocus: false) }
            env.app.search.query = "keep"

            let bad = try #require(URL(string: "fsearch://trash?path=/etc/passwd"))
            #expect(!pc.open(url: bad, app: env.app))
            #expect(!pc.isVisible)
            #expect(env.app.search.query == "keep")
        }

        @Test func appDelegateBuffersColdLaunchURLUntilConnectedAndForwardsAfter() throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let delegate = AppDelegate()

            let first = try #require(URL(string: "fsearch://search?q=early"))
            let ignored = try #require(URL(string: "https://example.com"))
            let second = try #require(URL(string: "fsearch://search?q=latest&mode=content"))

            // Before connect: buffered (latest valid wins); invalid URLs don't clobber it.
            delegate.application(NSApp, open: [first, second, ignored])
            #expect(env.panel.openedSearches.isEmpty)

            // Connecting flushes the buffered search once.
            delegate.connect(panel: env.panel, app: env.app)
            #expect(env.panel.openedSearches == [SearchURL(query: "latest", mode: .content)])

            // After connect: valid URLs forward immediately; invalid ones are ignored.
            let third = try #require(URL(string: "fsearch://search?q=live"))
            delegate.application(NSApp, open: [ignored])
            #expect(env.panel.openedSearches.count == 1)
            delegate.application(NSApp, open: [third])
            #expect(
                env.panel.openedSearches == [
                    SearchURL(query: "latest", mode: .content),
                    SearchURL(query: "live", mode: .names),
                ])
        }
    }
}
