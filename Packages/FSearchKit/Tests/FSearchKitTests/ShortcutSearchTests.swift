import FSearchKit
import Foundation
import Synchronization
import Testing

@Suite
struct ShortcutSearchTests {
    private final class StubBackend: SearchBackend, Sendable {
        struct State: Sendable {
            var searches: [(q: String, limit: Int)] = []
            var greps: [(q: String, pattern: String, mode: GrepMode)] = []
            var onSearch: @Sendable (String, Int) throws -> SearchReply = { _, _ in SearchReply(tookUs: 100, hits: []) }
            var onGrep: @Sendable (String, String, GrepMode) throws -> GrepReply = { _, _, _ in
                GrepReply(tookUs: 100, source: "index", candidates: 0, read: 0, complete: true, files: [])
            }
        }

        let state = Mutex(State())

        func search(_ q: String, limit: Int) async throws -> SearchReply {
            let handler = state.withLock { s -> (@Sendable (String, Int) throws -> SearchReply) in
                s.searches.append((q, limit))
                return s.onSearch
            }
            return try handler(q, limit)
        }

        func grep(q: String, pattern: String, mode: GrepMode) async throws -> GrepReply {
            let handler = state.withLock { s -> (@Sendable (String, String, GrepMode) throws -> GrepReply) in
                s.greps.append((q, pattern, mode))
                return s.onGrep
            }
            return try handler(q, pattern, mode)
        }

        func status() async throws -> DaemonStatus { throw DaemonError.disconnected }
        func ping() async throws {}
    }

    private func hit(_ path: String, score: Int32 = 10) -> Hit {
        Hit(path: path, kind: "file", size: 1, mtime: 0, score: score)
    }

    private func grepReply(_ paths: [String]) -> GrepReply {
        let files = paths.map { FileMatches(path: $0, matches: [Match(line: 1, text: "line")]) }
        return GrepReply(tookUs: 100, source: "index", candidates: files.count, read: files.count, complete: true, files: files)
    }

    @Test func blankOrZeroLimitQueriesReturnEmptyWithoutCallingBackend() async throws {
        let backend = StubBackend()
        #expect(try await ShortcutSearch.run(query: "", backend: backend).isEmpty)
        #expect(try await ShortcutSearch.run(query: "   \n\t\0  ", backend: backend).isEmpty)
        #expect(try await ShortcutSearch.run(query: "invoice", limit: 0, backend: backend).isEmpty)
        #expect(try await ShortcutSearch.run(query: "invoice", limit: -5, backend: backend).isEmpty)
        #expect(try await ShortcutSearch.run(query: "ext:swift", mode: .content, backend: backend).isEmpty)
        #expect(try await ShortcutSearch.run(query: "grep:", mode: .names, backend: backend).isEmpty)
        let counts = backend.state.withLock { ($0.searches.count, $0.greps.count) }
        #expect(counts == (0, 0))
    }

    @Test func nameSearchDeduplicatesCapsAndSanitizesQuery() async throws {
        let backend = StubBackend()
        backend.state.withLock { s in
            s.onSearch = { [self] _, _ in
                SearchReply(
                    tookUs: 100,
                    hits: [
                        hit("/p/a.txt", score: 100),
                        hit("/p/a.txt", score: 80),
                        hit("/p/b.txt", score: 70),
                        hit("/p/c.txt", score: 60),
                    ])
            }
        }
        let paths = try await ShortcutSearch.run(query: "foo\nbar\0baz", mode: .names, limit: 2, backend: backend)
        #expect(paths == ["/p/a.txt", "/p/b.txt"])
        let sent = backend.state.withLock { $0.searches }
        #expect(sent.count == 1)
        #expect(sent[0].q == "foo barbaz")
        #expect(sent[0].limit == 2)

        // Limit above maxLimit is capped at maxLimit.
        _ = try await ShortcutSearch.run(query: "invoice", limit: ShortcutSearch.maxLimit + 500, backend: backend)
        let cappedLimit = backend.state.withLock { $0.searches.last?.limit }
        #expect(cappedLimit == ShortcutSearch.maxLimit)
    }

    @Test func explicitLimitInQueryOverridesCallerLimitAndForwardsBadLimitsToDaemon() async throws {
        let backend = StubBackend()
        backend.state.withLock { s in
            s.onSearch = { [self] q, _ in
                if q.contains("limit:-5") { throw DaemonError.daemon("bad limit") }
                return SearchReply(tookUs: 100, hits: (0..<120).map { hit("/p/f\($0).txt") })
            }
        }

        let explicit = try await ShortcutSearch.run(query: "f limit:80", limit: 10, backend: backend)
        #expect(explicit.count == 80)

        await #expect(throws: DaemonError.daemon("bad limit")) {
            _ = try await ShortcutSearch.run(query: "f limit:-5", limit: 10, backend: backend)
        }
    }

    @Test func accentedNameQueryMergesBothUnicodeNormalForms() async throws {
        let backend = StubBackend()
        let nfc = "caf\u{00E9}"
        let nfd = "cafe\u{0301}"
        backend.state.withLock { s in
            s.onSearch = { [self] q, _ in
                if q.unicodeScalars.elementsEqual(nfc.unicodeScalars) {
                    return SearchReply(tookUs: 50, hits: [hit("/p/\(nfc).txt", score: 90)])
                }
                return SearchReply(tookUs: 50, hits: [hit("/p/\(nfd).txt", score: 120), hit("/p/other-\(nfd).txt", score: 60)])
            }
        }
        let paths = try await ShortcutSearch.run(query: nfc, limit: 5, backend: backend)
        #expect(paths.count == 2)
        #expect(paths[0] == "/p/\(nfd).txt")
        #expect(paths[1] == "/p/other-\(nfd).txt")
        let searchCount = backend.state.withLock { $0.searches.count }
        #expect(searchCount == 2)
    }

    @Test func contentSymbolsAndInlineGrepRouteToGrepAndApplyLimit() async throws {
        let backend = StubBackend()
        backend.state.withLock { s in
            s.onGrep = { [self] _, _, _ in
                grepReply(["/p/one.swift", "/p/one.swift", "/p/two.swift", "/p/three.swift"])
            }
        }

        let contentPaths = try await ShortcutSearch.run(query: "TODO ext:swift", mode: .content, limit: 2, backend: backend)
        #expect(contentPaths == ["/p/one.swift", "/p/two.swift"])
        let contentCall = backend.state.withLock { $0.greps.last }
        #expect(contentCall?.q == "ext:swift limit:2")
        #expect(contentCall?.pattern == "TODO")
        #expect(contentCall?.mode == .literal)

        // Default limit leaves filters untouched; explicit limit: in query isn't duplicated.
        _ = try await ShortcutSearch.run(query: "SearchModel", mode: .symbols, limit: ShortcutSearch.defaultLimit, backend: backend)
        let symCall = backend.state.withLock { $0.greps.last }
        #expect(symCall?.q == "")
        #expect(symCall?.pattern == "SearchModel")
        #expect(symCall?.mode == .symbol)

        _ = try await ShortcutSearch.run(query: "TODO limit:3", mode: .content, limit: 2, backend: backend)
        let explicitCall = backend.state.withLock { $0.greps.last }
        #expect(explicitCall?.q == "limit:3")

        // Inline regex:/grep:/sym: in names mode routes through grep.
        let inlinePaths = try await ShortcutSearch.run(query: "regex:fn\\s+main ext:rs", mode: .names, limit: 1, backend: backend)
        #expect(inlinePaths == ["/p/one.swift"])
        let inlineCall = backend.state.withLock { $0.greps.last }
        #expect(inlineCall?.q == "ext:rs limit:1")
        #expect(inlineCall?.pattern == "fn\\s+main")
        #expect(inlineCall?.mode == .regex)
    }

    /// Shortcuts gates every search that reads file contents, including inline content keys in names mode.
    @Test func readsFileContentsCoversContentModesAndInlineContentKeys() {
        #expect(ShortcutSearch.readsFileContents(query: "BEGIN RSA PRIVATE KEY", mode: .content))
        #expect(ShortcutSearch.readsFileContents(query: "", mode: .content))
        #expect(ShortcutSearch.readsFileContents(query: "SearchModel", mode: .symbols))
        #expect(!ShortcutSearch.readsFileContents(query: "invoice ext:pdf in:~/Documents", mode: .names))
        #expect(!ShortcutSearch.readsFileContents(query: "", mode: .names))
        for inline in ["ext:pem grep:BEGIN", "content:secret", "regex:TODO", "sym:Foo", "symbol:Foo", "\"grep:a b\"", "grep:"] {
            #expect(ShortcutSearch.readsFileContents(query: inline, mode: .names), "\(inline)")
        }
        // Same sanitizing as run(): a tab before the key still makes it a separate content-key word.
        #expect(ShortcutSearch.readsFileContents(query: "notes\tgrep:password", mode: .names))
    }

    @Test func readsFileContentsDetectsCombiningMarkPayloads() {
        let payloads = [
            "grep:\u{0301}secret",
            "grep:\"\u{0301}secret\"",
            "\"grep:\"\u{0301}secret",
            "\"\u{0301}\" grep:secret",
            "\"a\"\u{0301} grep:secret",
            "foo \u{0301} regex:\u{0301}token",
            "sym:\u{0301}foo",
        ]
        for query in payloads {
            #expect(ShortcutSearch.readsFileContents(query: query, mode: .names), "\(query)")
        }
        // Combining mark before key name changes the key itself to `\u{0301}grep`, matching daemon behavior.
        #expect(!ShortcutSearch.readsFileContents(query: "\"\u{0301}grep:secret\"", mode: .names))
    }

    @Test func combiningMarkInExplicitLimitForwardsLimitToDaemon() async throws {
        let backend = StubBackend()
        backend.state.withLock { s in
            s.onSearch = { [self] _, _ in
                SearchReply(tookUs: 100, hits: [hit("/p/a.txt"), hit("/p/b.txt"), hit("/p/c.txt")])
            }
        }
        // Caller limit 0 normally short-circuits, so reaching the backend proves hasExplicitLimit == true.
        let paths = try await ShortcutSearch.run(query: "foo limit:\u{0301}5", mode: .names, limit: 0, backend: backend)
        #expect(paths.count == 3)
        let sent = backend.state.withLock { $0.searches }
        #expect(sent.count == 1)
        #expect(sent[0].q == "foo limit:\u{0301}5")
    }

    @Test(.enabled(if: RealDaemon.binary != nil, "Vendor/fsearch not built"))
    func worksEndToEndAgainstRealDaemon() async throws {
        let nfdName = "cafe\u{0301}_notes.txt"
        let daemon = try RealDaemon(files: [
            "alpha.swift": "struct ShortcutNeedle {}\nlet tag = \"needle\"\n",
            "beta.swift": "let other = \"needle\"\n",
            "gamma.swift": "let third = \"needle\"\n",
            nfdName: "coffee notes\n",
        ])
        defer { withExtendedLifetime(daemon) {} }
        let client = DaemonClient(socketPath: daemon.socketPath, timeout: 5)
        // Wait until the daemon finishes indexing both file names and contents.
        var ready = false
        for _ in 0..<100 {
            if let s = try? await client.status(), s.entries >= 4, s.contentDocs >= 4, s.contentPending == 0 {
                ready = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        try #require(ready, "RealDaemon failed to index fixture files")

        // Name search with NFC query finds NFD filename.
        let accented = try await ShortcutSearch.run(query: "caf\u{00E9}", mode: .names, limit: 10, backend: client)
        #expect(accented.contains { $0.hasSuffix(nfdName) })

        // Content search honors custom limit: 2.
        let content = try await ShortcutSearch.run(query: "needle ext:swift", mode: .content, limit: 2, backend: client)
        #expect(content.count == 2)

        // Symbol search finds struct definition.
        let symbols = try await ShortcutSearch.run(query: "ShortcutNeedle", mode: .symbols, limit: 10, backend: client)
        #expect(symbols.count == 1)
        #expect(symbols.first?.hasSuffix("alpha.swift") == true)
    }
}
