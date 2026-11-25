import FSearchKit
import Foundation
import Testing

@Suite
struct SearchURLTests {
    private func parse(_ raw: String) -> SearchURL? {
        guard let url = URL(string: raw) else { return nil }
        return SearchURL.parse(url)
    }

    @Test func parsesEmptyAndPlainQueries() {
        #expect(parse("fsearch://search") == SearchURL(query: "", mode: .names))
        #expect(parse("fsearch://search/") == SearchURL(query: "", mode: .names))
        #expect(parse("fsearch://search?q=") == SearchURL(query: "", mode: .names))
        #expect(parse("fsearch://search?q") == SearchURL(query: "", mode: .names))
        #expect(parse("fsearch://search?q=invoice") == SearchURL(query: "invoice", mode: .names))
        #expect(parse("fsearch://search?q=invoice%20ext%3Apdf") == SearchURL(query: "invoice ext:pdf", mode: .names))
    }

    @Test func schemeHostAndModeAreCaseInsensitive() {
        #expect(parse("FSEARCH://SEARCH?q=heron") == SearchURL(query: "heron", mode: .names))
        #expect(parse("FSearch://Search/?Q=TODO&MODE=CONTENT") == SearchURL(query: "TODO", mode: .content))
        #expect(parse("fsearch://search?q=SearchModel&mode=Symbols") == SearchURL(query: "SearchModel", mode: .symbols))
        #expect(parse("fsearch://search?q=heron&mode=NAMES") == SearchURL(query: "heron", mode: .names))
    }

    @Test func supportsContentAndSymbolsModes() {
        #expect(parse("fsearch://search?q=TODO&mode=content") == SearchURL(query: "TODO", mode: .content))
        #expect(parse("fsearch://search?q=SearchModel&mode=symbols") == SearchURL(query: "SearchModel", mode: .symbols))
        #expect(parse("fsearch://search?mode=content") == SearchURL(query: "", mode: .content))
        #expect(parse("fsearch://search?mode=symbols") == SearchURL(query: "", mode: .symbols))
    }

    @Test func preservesLiteralPlusTrailingSpaceAndUnicode() {
        #expect(parse("fsearch://search?q=c++") == SearchURL(query: "c++", mode: .names))
        #expect(parse("fsearch://search?q=c%2B%2B") == SearchURL(query: "c++", mode: .names))
        #expect(parse("fsearch://search?q=in%3A~%2FDeveloper%20") == SearchURL(query: "in:~/Developer ", mode: .names))
        #expect(parse("fsearch://search?q=caf%C3%A9") == SearchURL(query: "café", mode: .names))
        #expect(parse("fsearch://search?q=%E6%97%A5%E6%9C%AC%E8%AA%9E") == SearchURL(query: "日本語", mode: .names))
    }

    @Test func lastQueryAndModeWinAndUnknownParamsAreIgnored() {
        #expect(parse("fsearch://search?q=first&q=second") == SearchURL(query: "second", mode: .names))
        #expect(parse("fsearch://search?mode=content&mode=symbols&q=x") == SearchURL(query: "x", mode: .symbols))
        #expect(parse("fsearch://search?q=foo&source=raycast&action=trash") == SearchURL(query: "foo", mode: .names))
        #expect(parse("fsearch://search?q=foo#ignored") == SearchURL(query: "foo", mode: .names))
    }

    @Test func sanitizesLineBreaksTabsAndControlCharacters() {
        #expect(parse("fsearch://search?q=one%0Atwo%0D%0Athree%0Dfour%09five") == SearchURL(query: "one two three four five", mode: .names))
        #expect(parse("fsearch://search?q=a%E2%80%A8b%E2%80%A9c") == SearchURL(query: "a b c", mode: .names))
        #expect(parse("fsearch://search?q=foo%00bar%1Bbaz%7Fqux") == SearchURL(query: "foobarbazqux", mode: .names))
        #expect(SearchURL(query: "line1\r\nline2\0\u{001B}").query == "line1 line2")
    }

    @Test func capsQueryLengthWithoutSplittingGraphemes() {
        let long = String(repeating: "a", count: SearchURL.maxQueryLength + 250)
        let parsed = parse("fsearch://search?q=\(long)")
        #expect(parsed?.query.unicodeScalars.count == SearchURL.maxQueryLength)

        // Multi-scalar emoji at the boundary must not be split mid-cluster.
        let family = "👨‍👩‍👧‍👦"  // 7 Unicode scalars
        #expect(family.unicodeScalars.count > 1)
        let prefix = String(repeating: "x", count: SearchURL.maxQueryLength - 1)
        let capped = SearchURL(query: prefix + family)
        #expect(capped.query == prefix)
        #expect(capped.query.unicodeScalars.count <= SearchURL.maxQueryLength)
    }

    @Test func rejectsUnknownSchemesHostsPathsAuthorityAndModes() {
        let bad = [
            "https://search?q=foo",
            "http://fsearch/search?q=foo",
            "file:///etc/passwd",
            "vscode://file/p/main.swift",
            "fsearch://",
            "fsearch:///search?q=foo",
            "fsearch://open?path=/etc/passwd",
            "fsearch://trash?path=/tmp/a",
            "fsearch://settings",
            "fsearch://search/extra?q=foo",
            "fsearch://user@search?q=foo",
            "fsearch://user:pass@search?q=foo",
            "fsearch://search:8080?q=foo",
            "fsearch://search?q=foo&mode=bogus",
            "fsearch://search?q=foo&mode=",
            "fsearch://search?q=foo&mode",
            "fsearch://search?mode=bogus&mode=content",
            "fsearch:search?q=foo",
        ]
        for raw in bad {
            #expect(parse(raw) == nil, "expected nil for \(raw)")
        }
    }

    @Test func buildsURLAndRoundTrips() {
        #expect(SearchURL().url.absoluteString == "fsearch://search")
        #expect(SearchURL(query: "", mode: .content).url.absoluteString == "fsearch://search?mode=content")
        #expect(SearchURL(query: "", mode: .symbols).url.absoluteString == "fsearch://search?mode=symbols")

        let samples: [SearchURL] = [
            SearchURL(query: "", mode: .names),
            SearchURL(query: "invoice ext:pdf", mode: .names),
            SearchURL(query: "TODO & FIXME = 100% #1 c++ \"a b\"", mode: .content),
            SearchURL(query: "café 日本語 🔍", mode: .symbols),
            SearchURL(query: "in:~/Developer ", mode: .names),
        ]
        for sample in samples {
            #expect(SearchURL.parse(sample.url) == sample, "round-trip failed for \(sample)")
        }
    }
}
