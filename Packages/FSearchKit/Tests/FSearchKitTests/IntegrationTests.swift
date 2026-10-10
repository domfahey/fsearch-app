import Foundation
import Testing
@testable import FSearchKit

@Suite(.enabled(if: RealDaemon.binary != nil, "run scripts/build-daemon.sh first"))
struct IntegrationTests {
    func waitReady(_ c: DaemonClient) async throws {
        for _ in 0..<200 {
            if let s = try? await c.status(), s.entries > 0 { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("daemon never became ready")
    }

    @Test func searchesByNameAndContent() async throws {
        let d = try RealDaemon(files: ["proj/heronfile.txt": "one\n  a heron needle  \n", "🏡 notes/a b.md": "x"])
        let c = DaemonClient(socketPath: d.socketPath)
        try await waitReady(c)
        let names = try await c.search("heronfile", limit: 50)
        #expect(names.hits.first?.path.hasSuffix("/proj/heronfile.txt") == true)
        let emoji = try await c.search("a b", limit: 50)
        #expect(emoji.hits.contains { $0.path.hasSuffix("/🏡 notes/a b.md") })
        // Content search waits for the content index to catch up.
        var grep: GrepReply?
        for _ in 0..<100 {
            grep = try? await c.grep(q: "", pattern: "heron needle", mode: .literal)
            if grep?.files.isEmpty == false { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(grep?.files.first?.matches.first?.line == 2)
    }
}
