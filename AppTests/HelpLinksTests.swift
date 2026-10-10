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
            #expect(HelpLinks.items.map(\.url.absoluteString) == [
                b + "docs/README.md", b + "docs/reference/keyboard-shortcuts.md",
                b + "docs/reference/query-syntax.md", b + "CHANGELOG.md", b + "docs/privacy.md"])
            #expect(HelpLinks.reportTitle == "Report an Issue…")
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
