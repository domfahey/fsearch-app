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
