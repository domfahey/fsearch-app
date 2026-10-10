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
    @Test func quotedKeyStillCountsAsAFilter() {
        // The daemon drops the quotes before looking for `key:`.
        #expect(QuerySplit.split(#""ext:rs" main"#) == ("main", #""ext:rs""#))
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
        #expect(QuerySplit.contentSearch("grep:") == nil)
        #expect(QuerySplit.contentSearch("std::grep") == nil)
    }
}

@Suite struct QuerySyntaxTests {
    @Test func cheatSheetListsTheFilters() {
        let text = QuerySyntax.cheatSheet.map(\.syntax).joined(separator: " ")
        for key in ["ext:", "in:", "type:", "kind:", "size:", "mtime:", "path:", "re:", "\""] {
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
