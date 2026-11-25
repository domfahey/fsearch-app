import AppIntents
import FSearchKit
import Foundation
import Testing

@testable import FSearch

extension AppTests {
    /// Shortcuts App Intents: `SearchFilesIntent`, `SearchModeOption`, and `FSearchShortcuts`.
    @Suite @MainActor
    struct AppIntentsTests {
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
