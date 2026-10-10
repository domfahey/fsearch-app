import Foundation
import Testing

@testable import FSearchKit

/// `resultsAreCurrent` is true only while `items` answer the query and mode
/// now in the box, so ↵ can't open a hit from the previous query.
@MainActor @Suite struct ResultsAreCurrentTests {
    @Test func freshModelIsCurrent() {
        let m = SearchModel(names: ScriptedBackend(), content: ScriptedBackend())
        #expect(m.resultsAreCurrent, "an empty box with no items: nothing stale to open")
    }

    @Test func currentAfterResultsLand() async {
        let m = SearchModel(names: ScriptedBackend(), content: ScriptedBackend())
        m.query = "a"
        await m.refresh()
        #expect(m.resultsAreCurrent)
    }

    @Test func typingMakesResultsStaleUntilTheRefreshLands() async {
        let m = SearchModel(names: ScriptedBackend(), content: ScriptedBackend())
        m.query = "a"
        await m.refresh()
        m.query = "ab"
        #expect(!m.resultsAreCurrent, "the items still answer \"a\"")
        await m.refresh()
        #expect(m.resultsAreCurrent)
    }

    @Test func changingModeMakesResultsStale() async {
        let m = SearchModel(names: ScriptedBackend(), content: ScriptedBackend())
        m.query = "a"
        await m.refresh()
        m.mode = .content
        #expect(!m.resultsAreCurrent, "the items are name hits, the mode is content")
        await m.refresh()
        #expect(m.resultsAreCurrent)
    }

    @Test func staleWhileTheNewSearchIsLoading() async throws {
        let b = HangingBackend(hangingQuery: "slow")
        let m = SearchModel(names: b, content: ScriptedBackend())
        m.query = "fast"
        await m.refresh()
        m.query = "slow"
        let t = Task { await m.refresh() }
        for _ in 0..<400 where !b.started { try await Task.sleep(for: .milliseconds(5)) }
        #expect(m.phase == .loading && m.items.map(\.path) == ["/r/fast"], "old items are kept while loading")
        #expect(!m.resultsAreCurrent)
        m.query = ""
        await m.refresh()
        await t.value
        #expect(m.resultsAreCurrent)
    }

    @Test func aLateReplyToAnOlderQueryIsNotCurrent() async throws {
        let b = ScriptedBackend()
        b.delays = ["old": 0.2]
        let m = SearchModel(names: b, content: ScriptedBackend())
        m.query = "old"
        let t = Task { await m.refresh() }
        try await Task.sleep(for: .milliseconds(20))
        m.query = "new"  // typed, but its refresh hasn't run yet
        await t.value
        #expect(!m.resultsAreCurrent)
    }

    @Test func errorsAndIdleAnswerTheirQuery() async {
        let b = ScriptedBackend()
        let m = SearchModel(names: b, content: ScriptedBackend())
        b.fail = .daemon("bad")
        m.query = "x"
        await m.refresh()
        #expect(m.resultsAreCurrent && m.items.isEmpty)
        m.query = "?"
        await m.refresh()
        #expect(m.resultsAreCurrent && m.phase == .idle)
    }
}
