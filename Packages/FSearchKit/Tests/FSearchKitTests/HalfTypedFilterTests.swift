import Foundation
import Testing

@testable import FSearchKit

@Suite struct HalfTypedFilterRuleTests {
    @Test func lastWordFilterKeyWithNoValueIsHalfTyped() {
        #expect(QuerySplit.endsInHalfTypedFilter("foo size:"))
        #expect(QuerySplit.endsInHalfTypedFilter("ext:"))
        #expect(QuerySplit.endsInHalfTypedFilter("foo in:"))
        #expect(QuerySplit.endsInHalfTypedFilter("foo mtime:"))
    }
    @Test func notHalfTyped() {
        #expect(!QuerySplit.endsInHalfTypedFilter("foo size:>1k"))
        #expect(!QuerySplit.endsInHalfTypedFilter("foo size: "), "a space ends the word: the user moved on")
        #expect(!QuerySplit.endsInHalfTypedFilter("size: foo"), "only the last word")
        #expect(!QuerySplit.endsInHalfTypedFilter("foo bar:"), "not a filter key")
        #expect(!QuerySplit.endsInHalfTypedFilter("foo grep:"), "content keys have their own rule")
        #expect(!QuerySplit.endsInHalfTypedFilter("foo"))
        #expect(!QuerySplit.endsInHalfTypedFilter(""))
        #expect(!QuerySplit.endsInHalfTypedFilter("EXT:"), "keys are case-sensitive")
    }

    /// A quoted word is text in content and symbols modes (QuerySplit.split), so it is never half-typed there;
    /// the daemon drops the quotes of a name query, so there it still is.
    @Test func aQuotedWordIsTextOutsideNameMode() {
        for mode in [SearchMode.content, .symbols] {
            for q in ["foo \"ext:", "\"size:", "foo \"type:c"] {
                #expect(!QuerySplit.endsInHalfTypedFilter(q, mode: mode), "\(q) \(mode)")
            }
            #expect(QuerySplit.endsInHalfTypedFilter("foo ext:", mode: mode))
            #expect(QuerySplit.endsInHalfTypedFilter("foo in:\"", mode: mode), "a quoted value on its way")
        }
        #expect(QuerySplit.endsInHalfTypedFilter("foo \"ext:", mode: .names))
        #expect(QuerySplit.endsInHalfTypedFilter("foo \"ext:"), "names by default")
    }
}

@MainActor @Suite struct HalfTypedFilterModelTests {
    @Test(arguments: [SearchMode.content, .symbols, .names])
    func halfTypedFilterIsNotSentAndKeepsResults(mode: SearchMode) async {
        let names = RecordingBackend(), content = RecordingBackend()
        let m = SearchModel(names: names, content: content)
        m.mode = mode
        m.query = "foo"
        await m.refresh()
        let before = (m.items, m.phase, m.lastTookUs)
        let sent = names.calls.count + content.calls.count
        #expect(sent == 1 && !m.items.isEmpty)
        m.query = "foo size:"
        await m.refresh()
        #expect(names.calls.count + content.calls.count == sent, "nothing new reaches the daemon")
        #expect(m.items == before.0 && m.phase == before.1 && m.lastTookUs == before.2)
    }

    @Test(arguments: [SearchMode.content, .symbols])
    func aQuotedWordIsSentAsText(mode: SearchMode) async {
        let content = RecordingBackend()
        let m = SearchModel(names: RecordingBackend(), content: content)
        m.mode = mode
        m.query = "foo"
        await m.refresh()
        m.query = "foo \"ext:"
        await m.refresh()
        #expect(content.calls.count == 2 && m.resultsAreCurrent, "\(content.calls)")
    }

    @Test(arguments: [SearchMode.content, .names])
    func finishedFilterIsSent(mode: SearchMode) async {
        let names = RecordingBackend(), content = RecordingBackend()
        let m = SearchModel(names: names, content: content)
        m.mode = mode
        m.query = "foo size:>1k"
        await m.refresh()
        #expect(names.calls.count + content.calls.count == 1)
    }

    @Test func halfTypedFilterKeepsAnErrorFromFlashingAgain() async {
        let b = ScriptedBackend()
        let m = SearchModel(names: b, content: ScriptedBackend())
        m.query = "foo"
        await m.refresh()
        b.fail = .badReply("bad size")
        m.query = "foo size:"
        await m.refresh()
        #expect(m.phase == .results, "no error shown while the filter is being typed")
    }
}

/// Item 29: a value on its way to a valid one is still being typed.
@Suite struct PartlyTypedValueTests {
    @Test(arguments: [
        "foo type:c", "type:co", "type:a", "type:code,", "type:code,im",
        "kind:fi", "kind:fo", "kind:li", "kind:sym",
        "size:1mb..", "size:>", "size:<", "size:>=", "size:<=", "mtime:<", "modified:>", "size:1mb.",
    ])
    func halfTyped(_ q: String) {
        #expect(QuerySplit.endsInHalfTypedFilter(q))
    }

    @Test(arguments: [
        "type:code", "type:app", "type:code,image", "type:zzz", "type:Code",
        "kind:d", "kind:f", "kind:file", "kind:xyz",
        "size:1mb..5mb", "size:>1k", "mtime:<7d", "ext:r", "in:~/D", "path:a.", "type:c ",
    ])
    func notHalfTyped(_ q: String) {
        #expect(!QuerySplit.endsInHalfTypedFilter(q))
    }
}

/// Item 28: the wait keeps older rows only while they're for the query being extended.
@MainActor @Suite struct HalfTypedWaitScopeTests {
    @Test func replacedQueryClearsInsteadOfWaiting() async {
        let names = RecordingBackend()
        let m = SearchModel(names: names, content: RecordingBackend())
        m.query = "foo"
        await m.refresh()
        m.query = "bar size:"  // select-all + paste
        await m.refresh()
        #expect(names.calls == ["search foo"], "still nothing sent for a half-typed filter")
        #expect(m.items.isEmpty && m.phase == .idle)
        #expect(m.resultsAreCurrent, "the empty list answers it")
    }

    @Test func modeChangeClearsInsteadOfWaiting() async {
        let names = RecordingBackend(), content = RecordingBackend()
        let m = SearchModel(names: names, content: content)
        m.query = "foo"
        await m.refresh()
        m.mode = .content
        m.query = "foo size:"
        await m.refresh()
        #expect(content.calls.isEmpty && m.items.isEmpty && m.phase == .idle, "name rows aren't shown in content mode")
    }

    @Test func extendingWaitsAndIsNotCurrent() async {
        let names = RecordingBackend()
        let m = SearchModel(names: names, content: RecordingBackend())
        m.query = "foo s"
        await m.refresh()
        for q in ["foo si", "foo siz", "foo size:", "foo size:>"] {
            m.query = q
            await m.refresh()
        }
        #expect(names.calls == ["search foo s", "search foo si", "search foo siz"])
        #expect(m.items.map(\.path) == ["/r/foo siz"], "the last finished query's rows stay up")
        #expect(!m.resultsAreCurrent, "they don't answer the half-typed query")
        m.query = "foo size:>1k"
        await m.refresh()
        #expect(names.calls.last == "search foo size:>1k" && m.resultsAreCurrent)
    }

    @Test func afterAClearFurtherTypingKeepsWaiting() async {
        let names = RecordingBackend()
        let m = SearchModel(names: names, content: RecordingBackend())
        m.query = "foo"
        await m.refresh()
        m.query = "bar size:"
        await m.refresh()
        m.query = "bar size:>"
        await m.refresh()
        #expect(names.calls == ["search foo"] && m.items.isEmpty)
    }
}
