import Testing

@testable import FSearchKit

@Suite struct QuerySplitTests {
    @Test func plainTextIsAllPattern() {
        #expect(QuerySplit.split("hello world") == ("hello world", ""))
    }
    @Test func filtersAreSplitOff() {
        #expect(QuerySplit.split("hello world ext:rs") == ("hello world", "ext:rs"))
        #expect(QuerySplit.split("in:~/projects TODO fix mtime:<7d") == ("TODO fix", "in:~/projects mtime:<7d"))
    }
    @Test func unknownKeysStayInThePattern() {
        #expect(QuerySplit.split("http://example.com") == ("http://example.com", ""))
        #expect(QuerySplit.split("std::vec") == ("std::vec", ""))
    }
    @Test func emptyAndSpaces() {
        #expect(QuerySplit.split("") == ("", ""))
        #expect(QuerySplit.split("   ext:md   ") == ("", "ext:md"))
    }
}

/// Parity with the daemon's `Query::filter` (fsearch src/query.rs). The keys
/// are copied from the daemon's match arms, not from QuerySplit.keys.
@Suite struct QuerySplitDaemonParityTests {
    static let daemonFilterKeys = ["ext", "type", "kind", "in", "size", "mtime", "modified", "re", "path", "limit"]
    static let daemonContentKeys: [(String, GrepMode)] = [
        ("grep", .literal), ("content", .literal), ("regex", .regex), ("sym", .symbol), ("symbol", .symbol),
    ]

    @Test(arguments: daemonFilterKeys)
    func everyDaemonFilterKeyIsSplitOff(_ key: String) {
        #expect(QuerySplit.split("todo \(key):v") == ("todo", "\(key):v"))
    }

    @Test(arguments: daemonContentKeys)
    func everyDaemonContentKeyStartsAContentSearch(_ key: String, _ mode: GrepMode) {
        let c = QuerySplit.contentSearch("main \(key):needle")
        #expect(c?.q == "main" && c?.pattern == "needle" && c?.mode == mode)
    }

    @Test func emptyValueIsText() {
        // A content pattern like `kind: Deployment` or `limit: 10` is text:
        // sent as a filter it would be a daemon error (or a match-all `path:`).
        #expect(QuerySplit.split("todo ext:") == ("todo ext:", ""))
        #expect(QuerySplit.split("in:") == ("in:", ""))
        #expect(QuerySplit.split(#"in:"""#) == (#"in:"""#, ""), "quotes around nothing are still nothing")
    }

    @Test(arguments: ["kind: Deployment", "size: 3", "type: module", "limit: 10", "path: str"])
    func yamlLikeTextIsThePattern(_ text: String) {
        #expect(QuerySplit.split(text) == (text, ""))
        #expect(QuerySplit.split("\(text) ext:yaml") == (text, "ext:yaml"))
    }

    @Test func keysAreCaseSensitive() {
        // The daemon matches keys exactly: EXT:rs is a plain word to it.
        #expect(QuerySplit.split("todo EXT:rs") == ("todo EXT:rs", ""))
        #expect(QuerySplit.contentSearch("GREP:x") == nil)
    }

    @Test func lastContentKeyWins() {
        let c = QuerySplit.contentSearch("grep:a regex:b")
        #expect(c?.pattern == "b" && c?.mode == .regex && c?.q == "")
    }

    @Test func contentKeysInContentModeStayInThePattern() {
        // A content-mode query is already the pattern: grep:/regex: in it are text, not filters.
        #expect(QuerySplit.split("grep:a regex:b ext:rs") == ("grep:a regex:b", "ext:rs"))
    }
}

@Suite struct QuerySplitSpacingTests {
    @Test func patternKeepsOriginalSpacing() {
        #expect(QuerySplit.split("foo  bar") == ("foo  bar", ""))
    }
    @Test func patternSpacingSurvivesFilterRemoval() {
        #expect(QuerySplit.split("foo  bar ext:rs") == ("foo  bar", "ext:rs"))
    }
    @Test func leadingSpacesAreTrimmed() {
        #expect(QuerySplit.split("  indented code").pattern == "indented code")
    }
}

/// Quoting follows the daemon's split_words: a "double quoted" run is one
/// word (spaces inside don't split it), and the quotes stay on the word so
/// the daemon sees the same thing when the filters are sent back.
@Suite struct QuerySplitQuotingTests {
    @Test func quotedFilterValueIsOneWord() {
        #expect(QuerySplit.split(#"in:"~/My Stuff" todo"#) == ("todo", #"in:"~/My Stuff""#))
    }
    @Test func quotedPatternKeepsQuotesAndSpacing() {
        #expect(QuerySplit.split(#""a  b" ext:md  c"#) == (#""a  b"  c"#, "ext:md"))
    }
    @Test func aWordStartingWithAQuoteIsText() {
        // Quoting is how to search for filter-looking text.
        #expect(QuerySplit.split(#""ext:rs" main"#) == (#""ext:rs" main"#, ""))
        #expect(QuerySplit.split(#""kind: Deployment""#) == (#""kind: Deployment""#, ""))
    }
    @Test func unclosedQuoteRunsToTheEnd() {
        #expect(QuerySplit.split(#"in:"~/My Stuff todo"#) == ("", #"in:"~/My Stuff todo"#))
    }
    @Test func wordsSplitLikeTheDaemon() {
        #expect(QuerySplit.words(#"a "b c"  d"#) == ["a", #""b c""#, "d"])
        #expect(QuerySplit.unquoted(#"in:"~/My Stuff""#) == "in:~/My Stuff")
    }
}

/// grep:/content:/regex:/sym:/symbol: in a name search make the daemon answer
/// with lines, so the panel runs that query as a content search.
@Suite struct ContentKeyTests {
    @Test func grepKeyBecomesTheLiteralPattern() {
        let c = QuerySplit.contentSearch("main grep:needle ext:rs")
        #expect(c?.pattern == "needle" && c?.mode == .literal && c?.q == "main ext:rs")
    }
    @Test func eachKeyPicksItsMode() {
        #expect(QuerySplit.contentSearch("content:x")?.mode == .literal)
        #expect(QuerySplit.contentSearch("regex:ne+dle")?.mode == .regex)
        #expect(QuerySplit.contentSearch("sym:apply")?.mode == .symbol)
        #expect(QuerySplit.contentSearch("symbol:apply")?.mode == .symbol)
    }
    @Test func quotedValueLosesItsQuotes() {
        #expect(QuerySplit.contentSearch(#"grep:"two words""#)?.pattern == "two words")
    }
    @Test func noKeyNoContentSearch() {
        #expect(QuerySplit.contentSearch("main.rs ext:rs") == nil)
        #expect(QuerySplit.contentSearch("std::grep") == nil)
    }
}

@Suite struct EmptyContentKeyTests {
    // The daemon treats an empty-valued content key as a content search too.
    @Test func emptyValueStillCountsAsTheKey() {
        let c = QuerySplit.contentSearch("main grep:")
        #expect(c?.pattern == "" && c?.mode == .literal && c?.q == "main")
        #expect(QuerySplit.contentSearch(#"grep:"""#)?.pattern == "")
        #expect(QuerySplit.contentSearch("regex:")?.mode == .regex)
        #expect(QuerySplit.contentSearch("sym:")?.mode == .symbol)
    }
}

@Suite struct QuerySyntaxTests {
    @Test func cheatSheetListsTheFilters() {
        let text = QuerySyntax.cheatSheet.map(\.syntax).joined(separator: " ")
        for key in ["ext:", "in:", "type:", "kind:", "size:", "mtime:", "path:", "re:", "limit:", "\""] {
            #expect(text.contains(key), "cheat sheet mentions \(key)")
        }
        #expect(QuerySyntax.cheatSheet.allSatisfy { !$0.meaning.isEmpty })
    }
    @Test func onlyAQuestionMarkShowsIt() {
        #expect(QuerySyntax.isCheatSheet("?"))
        #expect(!QuerySyntax.isCheatSheet("a?"))
        #expect(!QuerySyntax.isCheatSheet(""))
    }
}

/// What reaches the daemon for filter-looking text in content and symbol searches.
@MainActor @Suite struct ContentModeFilterWordTests {
    @Test(arguments: [SearchMode.content, .symbols])
    func bareKeyIsSentAsPattern(mode: SearchMode) async {
        let content = RecordingBackend()
        let m = SearchModel(names: RecordingBackend(), content: content)
        m.mode = mode
        m.query = "kind: Deployment ext:yaml"
        await m.refresh()
        let grepMode = mode == .symbols ? "symbol" : "literal"
        #expect(content.calls == ["grep ext:yaml|kind: Deployment|\(grepMode)"])
    }

    @Test func emptyPathIsNotAMatchAllFilter() async {
        let content = RecordingBackend()
        let m = SearchModel(names: RecordingBackend(), content: content)
        m.mode = .content
        m.query = "path: str"
        await m.refresh()
        #expect(content.calls == ["grep |path: str|literal"])
    }
}
