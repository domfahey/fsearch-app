import Foundation
import Testing

@testable import FSearchKit

/// Verifies the ranking, typo-tolerance, word-combining, and `limit:` behavior
/// documented in `docs/reference/query-syntax.md` against the bundled daemon.
@Suite(.enabled(if: RealDaemon.binary != nil, "run scripts/build-daemon.sh first"))
struct QueryBehaviorTests {
    private func waitReady(_ client: DaemonClient, minEntries: Int, minContentDocs: Int) async throws {
        for _ in 0..<200 {
            if let s = try? await client.status(),
                s.entries >= minEntries, s.contentDocs >= minContentDocs, s.contentPending == 0
            {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("daemon never finished indexing fixture")
    }

    @Test func documentedRankingTypoCombiningAndLimitBehaviorsMatchDaemon() async throws {
        var files: [String: String] = [
            // Ranking (normalized mtime applied below)
            "rank/foo.txt": "x\n",
            "rank/foo_bar.txt": "x\n",
            "rank/my_foo.txt": "x\n",
            "rank/xfooy.txt": "x\n",
            "rank/f_o_o.txt": "x\n",
            "rank2/foo": "x\n",
            // Recency
            "rec/old_heron.txt": "x\n",
            "rec/new_heron.txt": "x\n",
            // Typo tolerance
            "typo/bird.txt": "x\n",
            "typo/alpha.txt": "x\n",
            "typo/abcdefgh.txt": "x\n",
            "myfolder/target.txt": "x\n",
            // Word combining
            "projects/2026/invoice_march.pdf": "x\n",
            "projects/archive/invoice_old.pdf": "x\n",
            "alpha_dir/beta_dir/gamma_file.txt": "x\n",
            "a1_b2_c3_d4_e5_f6_g7_h8_i9_j0.txt": "x\n",
            "neg/h_e_r_o_n.txt": "x\n",
            "neg/heron.txt": "x\n",
            // Symbols + multi-line grep
            "sym/multi.rs": (0..<8).map { "needle line \($0)" }.joined(separator: "\n") + "\npub fn heron_func() {}\n",
        ]
        for i in 0..<60 {
            files[String(format: "many/item_%02d.rs", i)] = "needle_many \(i)\npub fn shared_sym() {}\n"
        }

        let d = try RealDaemon(files: files)
        defer { withExtendedLifetime(d) {} }

        // Equalize mtimes in rank/ and rank2/, and separate old vs new in rec/.
        let fm = FileManager.default
        let steady = Date(timeIntervalSinceNow: -86_400 * 30)
        for rel in ["rank/foo.txt", "rank/foo_bar.txt", "rank/my_foo.txt", "rank/xfooy.txt", "rank/f_o_o.txt", "rank2/foo"] {
            try fm.setAttributes([.modificationDate: steady], ofItemAtPath: d.root.appendingPathComponent(rel).path)
        }
        try fm.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -86_400 * 365)],
            ofItemAtPath: d.root.appendingPathComponent("rec/old_heron.txt").path)
        try fm.setAttributes(
            [.modificationDate: Date()], ofItemAtPath: d.root.appendingPathComponent("rec/new_heron.txt").path)

        let c = DaemonClient(socketPath: d.socketPath)
        try await waitReady(c, minEntries: files.count, minContentDocs: 60)

        // 1. Ranking: exact name > exact stem > prefix > word boundary > mid-word/fuzzy; recency breaks equal ties.
        let ranked = try await c.search("foo", limit: 20).hits.map { ($0.path as NSString).lastPathComponent }
        let idxExact = try #require(ranked.firstIndex(of: "foo"))
        let idxStem = try #require(ranked.firstIndex(of: "foo.txt"))
        let idxPrefix = try #require(ranked.firstIndex(of: "foo_bar.txt"))
        let idxBoundary = try #require(ranked.firstIndex(of: "my_foo.txt"))
        let idxMid = try #require(ranked.firstIndex(of: "xfooy.txt"))
        #expect(idxExact < idxStem && idxStem < idxPrefix && idxPrefix < idxBoundary && idxBoundary < idxMid)

        let recency = try await c.search("in:\(d.root.path)/rec heron", limit: 10).hits
        #expect(recency.map { ($0.path as NSString).lastPathComponent } == ["new_heron.txt", "old_heron.txt"])

        // 2. Typo tolerance: 5+ chars allows 1 edit (except first char); 4 chars, 2 edits, and modifiers do not.
        let inTypo = "in:\(d.root.path)/typo"
        #expect(try await c.search("\(inTypo) alpxa", limit: 5).hits.contains { $0.path.hasSuffix("/alpha.txt") })
        #expect(try await c.search("\(inTypo) alhpa", limit: 5).hits.contains { $0.path.hasSuffix("/alpha.txt") })
        #expect(try await c.search("\(inTypo) alppha", limit: 5).hits.contains { $0.path.hasSuffix("/alpha.txt") })
        #expect(try await c.search("\(inTypo) xlpha", limit: 5).hits.isEmpty, "first character must match")
        #expect(try await c.search("\(inTypo) byrd", limit: 5).hits.isEmpty, "4-char substitution is not tolerated")
        #expect(try await c.search("\(inTypo) brid", limit: 5).hits.isEmpty, "4-char transposition is not tolerated")
        #expect(try await c.search("\(inTypo) abxdxfgh", limit: 5).hits.isEmpty, "two edits are not tolerated")
        #expect(try await c.search("\(inTypo) 'alpxa", limit: 5).hits.isEmpty, "exact modifier disables typos")
        #expect(try await c.search("\(inTypo) ^alpxa", limit: 5).hits.isEmpty, "prefix modifier disables typos")
        #expect(try await c.search("\(inTypo) alpxa$", limit: 5).hits.isEmpty, "suffix modifier disables typos")
        #expect(try await c.search("myfoldxr target", limit: 5).hits.contains { $0.path.hasSuffix("/myfolder/target.txt") })

        // 3. Word combining: order-independent AND, at least one word in entry name, 8-word cap, substring `!word`.
        let forward = try await c.search("projects invoice", limit: 10).hits.map(\.path)
        let reversed = try await c.search("invoice projects", limit: 10).hits.map(\.path)
        #expect(forward == reversed && forward.count == 2)
        #expect(try await c.search("alpha_dir beta_dir ext:txt", limit: 10).hits.isEmpty, "at least one word must match the file name")
        #expect(try await c.search("alpha_dir gamma_file", limit: 5).hits.contains { $0.path.hasSuffix("/gamma_file.txt") })
        #expect(
            try await c.search("a1 b2 c3 d4 e5 f6 g7 h8 nonexistent9", limit: 5).hits.contains {
                $0.path.hasSuffix("/a1_b2_c3_d4_e5_f6_g7_h8_i9_j0.txt")
            }, "9th positive word is ignored")
        #expect(try await c.search("a1 b2 c3 d4 e5 f6 g7 nonexistent8", limit: 5).hits.isEmpty, "8th positive word is checked")
        let negated = try await c.search("in:\(d.root.path)/neg heron !heron", limit: 10).hits.map {
            ($0.path as NSString).lastPathComponent
        }
        #expect(negated == ["h_e_r_o_n.txt"], "!word is an exact substring exclusion, not fuzzy")

        // 4. limit: works in name, content, and symbol search; last wins; 0 returns empty; invalid errors; grep caps 5 lines/file.
        #expect(try await c.search("item limit:5", limit: 50).hits.count == 5)
        #expect(try await c.search("item limit:60", limit: 50).hits.count == 60)
        #expect(try await c.search("item limit:0", limit: 50).hits.isEmpty)
        #expect(try await c.search("item limit:1 limit:7", limit: 50).hits.count == 7)
        await #expect(throws: DaemonError.daemon("bad limit")) {
            _ = try await c.search("item limit:abc", limit: 50)
        }

        #expect(try await c.grep(q: "limit:5", pattern: "needle_many", mode: .literal).files.count == 5)
        #expect(try await c.grep(q: "limit:60", pattern: "needle_many", mode: .literal).files.count == 60)
        let perFile = try await c.grep(q: "", pattern: "needle line", mode: .literal).files
        #expect(perFile.first?.matches.count == 5, "content search returns at most 5 matching lines per file by default")

        #expect(try await c.grep(q: "", pattern: "heron_func", mode: .symbol).files.count == 1)
        #expect(try await c.grep(q: "", pattern: "heron", mode: .symbol).files.isEmpty, "symbol search matches full symbol names")
        #expect(try await c.grep(q: "limit:5", pattern: "shared_sym", mode: .symbol).files.count == 5)
        #expect(try await c.grep(q: "limit:60", pattern: "shared_sym", mode: .symbol).files.count == 60)
    }
}
