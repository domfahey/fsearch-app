import FSearchKit
import Foundation
import Testing

@testable import FSearch

extension AppTests {
    @Suite @MainActor
    struct HelpLinksTests {
        @Test func menuTitlesAndUrls() {
            let b = "https://github.com/domfahey/fsearch-app/blob/main/"
            #expect(HelpLinks.items.map(\.title) == ["FSearch Help", "Keyboard Shortcuts", "Query Syntax", "Changelog", "Privacy"])
            #expect(
                HelpLinks.items.map(\.url.absoluteString) == [
                    b + "docs/README.md", b + "docs/reference/keyboard-shortcuts.md",
                    b + "docs/reference/query-syntax.md", b + "CHANGELOG.md", b + "docs/privacy.md",
                ])
            #expect(HelpLinks.reportTitle == "Report an Issue…")
        }

        @Test func communityLinks() {
            #expect(HelpLinks.community.map(\.title) == ["GitHub", "Discussions"])
            #expect(
                HelpLinks.community.map(\.url.absoluteString) == [
                    "https://github.com/domfahey/fsearch-app", "https://github.com/domfahey/fsearch-app/discussions",
                ])
        }

        /// The panel's FSearch menu looks links up by title, so it and the menu bar can't drift.
        @Test func lookupByTitle() {
            let b = "https://github.com/domfahey/fsearch-app/blob/main/"
            #expect(HelpLinks.item("FSearch Help")?.url.absoluteString == b + "docs/README.md")
            #expect(HelpLinks.item("Changelog")?.url.absoluteString == b + "CHANGELOG.md")
            #expect(HelpLinks.item("Discussions")?.url.absoluteString == "https://github.com/domfahey/fsearch-app/discussions")
            #expect(HelpLinks.item("Nope") == nil)
        }

        @Test func installKind() {
            #expect(HelpLinks.install(owns: true, state: .failed) == .bundled)
            #expect(HelpLinks.install(owns: false, state: .running) == .cli)
            #expect(HelpLinks.install(owns: false, state: .failed) == .unsure)
        }

        @Test func reportOpensThePrefilledFormThroughTheWorkspace() {
            let env = TestEnv()
            defer { env.tearDown() }
            HelpLinks.reportIssue(daemon: env.app.daemon, workspace: env.workspace)
            let url = env.workspace.opened.first?.absoluteString ?? ""
            #expect(url.hasPrefix("https://github.com/domfahey/fsearch-app/issues/new?template=bug_report.yml"))
            #expect(url.contains("macos="))
        }
    }
}
