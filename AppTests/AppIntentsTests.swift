import AppIntents
import AppKit
import FSearchKit
import Foundation
import SwiftUI
import Testing

@testable import FSearch

extension AppTests {
    /// Shortcuts App Intents: `SearchFilesIntent`, `SearchModeOption`, and `FSearchShortcuts`.
    /// Serialized: the backend and content-search seams are process-wide.
    @Suite(.serialized) @MainActor
    struct AppIntentsTests {
        /// Swaps the content-search opt-in for one test; returns the restore closure.
        func allowContentSearch(_ allowed: Bool) -> () -> Void {
            let saved = SearchFilesIntent.contentSearchAllowed.withLock { current in
                let old = current
                current = { allowed }
                return old
            }
            return { SearchFilesIntent.contentSearchAllowed.withLock { $0 = saved } }
        }

        @Test func searchFilesIntentReturnsMatchingIntentFilesInOrder() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let alpha = env.file("alpha.txt", "hello")
            let beta = env.file("nested/beta.pdf", "world")
            env.daemon.onSearch = { _ in
                SearchReply(tookUs: 350, hits: [Wire.hit(alpha), Wire.hit(beta)])
            }
            let saved = SearchFilesIntent.backendFactory.withLock { current in
                let old = current
                current = { env.daemon }
                return old
            }
            defer { SearchFilesIntent.backendFactory.withLock { $0 = saved } }

            let intent = SearchFilesIntent()
            intent.query = "alpha"
            intent.mode = .names
            intent.limit = 10

            let result = try await intent.perform()
            let files = try #require(result.value)
            #expect(files.map(\.fileURL) == [URL(fileURLWithPath: alpha), URL(fileURLWithPath: beta)])
            #expect(env.daemon.searches == ["alpha"])
        }

        @Test func searchFilesIntentSupportsContentAndSymbolsModes() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let swiftFile = env.file("SearchModel.swift", "final class SearchModel {}")
            env.daemon.onGrep = { _, _, _ in
                Wire.grep([(swiftFile, [(1, "final class SearchModel {}")])])
            }
            let saved = SearchFilesIntent.backendFactory.withLock { current in
                let old = current
                current = { env.daemon }
                return old
            }
            defer { SearchFilesIntent.backendFactory.withLock { $0 = saved } }
            let restore = allowContentSearch(true)
            defer { restore() }

            let contentIntent = SearchFilesIntent()
            contentIntent.query = "SearchModel ext:swift"
            contentIntent.mode = .content
            contentIntent.limit = 25
            let contentFiles = try #require(try await contentIntent.perform().value)
            #expect(contentFiles.map(\.fileURL) == [URL(fileURLWithPath: swiftFile)])
            #expect(env.daemon.greps.last?.mode == .literal)
            #expect(env.daemon.greps.last?.q == "ext:swift limit:25")
            #expect(env.daemon.greps.last?.pattern == "SearchModel")

            let symbolsIntent = SearchFilesIntent()
            symbolsIntent.query = "SearchModel"
            symbolsIntent.mode = .symbols
            symbolsIntent.limit = 50
            let symbolFiles = try #require(try await symbolsIntent.perform().value)
            #expect(symbolFiles.map(\.fileURL) == [URL(fileURLWithPath: swiftFile)])
            #expect(env.daemon.greps.last?.mode == .symbol)
            #expect(env.daemon.greps.last?.q == "")
        }

        @Test func searchFilesIntentPropagatesDaemonErrorsAndNeverOpensPanel() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            env.daemon.onSearch = { _ in throw DaemonError.disconnected }
            let saved = SearchFilesIntent.backendFactory.withLock { current in
                let old = current
                current = { env.daemon }
                return old
            }
            defer { SearchFilesIntent.backendFactory.withLock { $0 = saved } }

            let intent = SearchFilesIntent()
            intent.query = "invoice"
            intent.mode = .names
            intent.limit = 50

            await #expect(throws: DaemonError.disconnected) {
                _ = try await intent.perform()
            }
            #expect(!SearchFilesIntent.openAppWhenRun)
            #expect(env.panel.shows == 0)
        }

        /// With the opt-in off, Inside Files, Definitions and inline content keys never reach the daemon.
        @Test func searchFilesIntentRefusesContentSearchesUntilAllowed() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let saved = SearchFilesIntent.backendFactory.withLock { current in
                let old = current
                current = { env.daemon }
                return old
            }
            defer { SearchFilesIntent.backendFactory.withLock { $0 = saved } }
            let restore = allowContentSearch(false)
            defer { restore() }

            for (query, mode) in [
                ("BEGIN RSA PRIVATE KEY", SearchModeOption.content), ("SearchModel", .symbols), ("ext:pem grep:BEGIN", .names),
            ] {
                let intent = SearchFilesIntent()
                intent.query = query
                intent.mode = mode
                intent.limit = 50
                await #expect(throws: SearchFilesIntentError.contentSearchNotAllowed) {
                    _ = try await intent.perform()
                }
            }
            #expect(env.daemon.greps.isEmpty)
            #expect(env.daemon.searches.isEmpty)

            // File Names mode stays available without the opt-in.
            let alpha = env.file("alpha.txt")
            env.daemon.onSearch = { _ in SearchReply(tookUs: 1, hits: [Wire.hit(alpha)]) }
            let names = SearchFilesIntent()
            names.query = "alpha"
            names.mode = .names
            names.limit = 5
            #expect(try #require(try await names.perform().value).map(\.fileURL) == [URL(fileURLWithPath: alpha)])
        }

        /// The refusal tells the user which setting to turn on, in a localized message.
        @Test func contentSearchRefusalNamesTheSetting() {
            let error = SearchFilesIntentError.contentSearchNotAllowed
            let text = String(localized: error.localizedStringResource)
            #expect(text.contains("Settings"))
            #expect(text.contains(String(localized: SearchFilesIntent.allowContentSearchTitle)))
            #expect(error.localizedDescription == text)
        }

        /// The opt-in is off by default, lives under its own defaults key, and the uninstaller resets it.
        @Test func contentSearchOptInDefaultsOffAndIsResetByUninstall() {
            let env = TestEnv()
            defer { env.tearDown() }
            #expect(!SearchFilesIntent.contentSearchAllowed(in: env.defaults))
            #expect(!env.app.allowShortcutsContentSearch)
            env.app.allowShortcutsContentSearch = true
            #expect(env.defaults.bool(forKey: SearchFilesIntent.allowContentSearchKey))
            #expect(SearchFilesIntent.contentSearchAllowed(in: env.defaults))
            #expect(Uninstaller.defaultsKeys.contains(SearchFilesIntent.allowContentSearchKey))
            // The live gate reads the app's store (this host's throwaway suite), where nothing turned it on.
            #expect(!SearchFilesIntent.contentSearchAllowed.withLock { $0 }())
        }

        /// Settings shows the opt-in toggle, off, and pressing it turns content searches on.
        @Test func settingsToggleAllowsShortcutsContentSearch() async throws {
            let env = TestEnv()
            defer { env.tearDown() }
            let u = Uninstaller(
                helper: nil, loginItem: nil, workspace: env.workspace, defaults: env.defaults,
                dataFolder: env.dir, logFolder: env.dir, exists: { _ in false }, cliAgentInstalled: { false }, resetShortcut: {})
            let w = await render(
                SettingsView(loginItem: LoginItemModel(service: nil), uninstaller: u).environmentObject(env.app),
                size: NSSize(width: 440, height: 700))
            defer { w.close() }
            let toggle = try #require(await axWait(String(localized: SearchFilesIntent.allowContentSearchTitle), in: w))
            #expect(!env.app.allowShortcutsContentSearch)
            toggle.press()
            #expect(await eventually { env.app.allowShortcutsContentSearch })
            #expect(env.defaults.bool(forKey: SearchFilesIntent.allowContentSearchKey))
        }

        @Test func shortcutsMetadataAndModeMappingsAreConfigured() {
            #expect(SearchModeOption.names.searchMode == .names)
            #expect(SearchModeOption.content.searchMode == .content)
            #expect(SearchModeOption.symbols.searchMode == .symbols)
            #expect(SearchModeOption.caseDisplayRepresentations.count == 3)
            #expect(!FSearchShortcuts.appShortcuts.isEmpty)
            _ = SearchFilesIntent.parameterSummary
            // Default backend points at LaunchOptions.current.socketPath (never the real daemon in unit tests).
            let defaultBackend = SearchFilesIntent.defaultBackend()
            #expect(defaultBackend is DaemonClient)
        }
    }
}
