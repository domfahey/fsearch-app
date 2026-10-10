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
